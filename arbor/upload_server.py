#!/usr/bin/env python3
"""
ARBOR: Recursive Directory Upload Web Server

A lightweight Python web server that provides a browser-based interface for
selecting a local directory and recursively uploading its entire contents to
the server, preserving the original directory structure, file permissions,
and timestamps.
"""

import asyncio
import argparse
import hashlib
import json
import logging
import mimetypes
import os
import shutil
import sys
import tempfile
import time
import uuid
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, List, Optional, Any
from urllib.parse import unquote

import aiofiles
import yaml
from fastapi import FastAPI, File, UploadFile, HTTPException, WebSocket, WebSocketDisconnect, Depends, Form, Request, status, BackgroundTasks
from fastapi.responses import HTMLResponse, FileResponse, StreamingResponse, JSONResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel, Field
import uvicorn

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


# ============================================================================
# Configuration Models
# ============================================================================

class ServerConfig(BaseModel):
    """Server configuration"""
    host: str = "127.0.0.1"
    port: int = 8196
    upload_dir: str = "./uploads"
    max_file_size: int = 100 * 1024 * 1024  # 100MB
    max_session_size: int = 100 * 1024 * 1024 * 1024  # 100GB
    chunk_size: int = 1024 * 1024  # 1MB
    workers: int = 16


class CompressionConfig(BaseModel):
    """Compression configuration"""
    enabled: bool = True
    algorithms: List[str] = ["gzip", "br"]
    level: int = 6


class SecurityConfig(BaseModel):
    """Security configuration"""
    auth_enabled: bool = False
    allowed_extensions: List[str] = []
    blocked_extensions: List[str] = [".exe", ".bat", ".cmd", ".sh"]
    rate_limit: str = "100/minute"
    secret_key: str = "change-me-in-production"


class LoggingConfig(BaseModel):
    """Logging configuration"""
    level: str = "INFO"
    file: Optional[str] = None
    format: str = "json"


class GitLabConfig(BaseModel):
    """GitLab integration configuration"""
    enabled: bool = False
    repository_url: str = ""
    ssh_key_path: str = ""
    gpg_key_id: str = ""
    auto_push: bool = False
    branch: str = "main"


class AppConfig(BaseModel):
    """Application configuration"""
    server: ServerConfig = Field(default_factory=ServerConfig)
    compression: CompressionConfig = Field(default_factory=CompressionConfig)
    security: SecurityConfig = Field(default_factory=SecurityConfig)
    logging: LoggingConfig = Field(default_factory=LoggingConfig)
    gitlab: GitLabConfig = Field(default_factory=GitLabConfig)


# ============================================================================
# Data Models
# ============================================================================

class FileMetadata(BaseModel):
    """File metadata schema"""
    relativePath: str
    originalName: str
    size: int
    mode: Optional[int] = None
    mtime: float
    atime: Optional[float] = None
    ctime: Optional[float] = None
    sha256: str
    compressed: bool = False
    compressionType: Optional[str] = None


class UploadSession(BaseModel):
    """Upload session data"""
    session_id: str
    user_id: Optional[str] = None
    created_at: float
    start_time: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    total_files: int = 0
    completed_files: int = 0
    total_bytes: int = 0
    transferred_bytes: int = 0
    status: str = "active"  # active, paused, completed, cancelled, failed
    current_file: Optional[str] = None
    files_metadata: List[FileMetadata] = []
    errors: List[Dict[str, str]] = []


class ProgressMessage(BaseModel):
    """WebSocket progress message"""
    type: str  # progress, error, complete, pause, resume, cancel
    sessionId: str
    payload: Dict[str, Any]


class LoginRequest(BaseModel):
    """Login request"""
    username: str
    password: str


class User(BaseModel):
    """User model"""
    username: str
    hashed_password: str
    role: str = "user"  # user, admin


# ============================================================================
# Global State
# ============================================================================

# Configuration
config = AppConfig()

# Active upload sessions
upload_sessions: Dict[str, UploadSession] = {}

# WebSocket connections
websocket_connections: Dict[str, WebSocket] = {}

# Password context for hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Dummy user database (in production, use a proper database)
users_db: Dict[str, User] = {
    "admin": User(
        username="admin",
        hashed_password=pwd_context.hash("admin"),
        role="admin"
    )
}

# HTTP Bearer for authentication
security_scheme = HTTPBearer(auto_error=False)


# ============================================================================
# Authentication Functions
# ============================================================================

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Create JWT access token"""
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(hours=24)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, config.security.secret_key, algorithm="HS256")
    return encoded_jwt


def verify_token(credentials: Optional[HTTPAuthorizationCredentials]) -> Optional[str]:
    """Verify JWT token and return username"""
    if not config.security.auth_enabled:
        return "anonymous"
    
    if credentials is None:
        return None
    
    try:
        token = credentials.credentials
        payload = jwt.decode(token, config.security.secret_key, algorithms=["HS256"])
        username: str = payload.get("sub")
        if username is None:
            return None
        return username
    except JWTError:
        return None


async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security_scheme)) -> str:
    """Get current authenticated user"""
    username = verify_token(credentials)
    if username is None and config.security.auth_enabled:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return username or "anonymous"


# ============================================================================
# Utility Functions
# ============================================================================

def sanitize_path(path: str) -> str:
    """Sanitize path to prevent directory traversal attacks"""
    # Remove any leading slashes and resolve .. components
    path = path.lstrip('/')
    parts = []
    for part in path.split('/'):
        if part == '..':
            if parts:
                parts.pop()
        elif part and part != '.':
            parts.append(part)
    return '/'.join(parts)


def is_extension_allowed(filename: str) -> bool:
    """Check if file extension is allowed"""
    ext = Path(filename).suffix.lower()
    
    # Check blocked extensions first
    if ext in config.security.blocked_extensions:
        return False
    
    # If allowed_extensions is empty, allow all (except blocked)
    if not config.security.allowed_extensions:
        return True
    
    # Check if extension is in allowed list
    return ext in config.security.allowed_extensions


def parse_size(size_str: str) -> int:
    """Parse size string (e.g., '100MB') to bytes"""
    units = {'B': 1, 'KB': 1024, 'MB': 1024**2, 'GB': 1024**3, 'TB': 1024**4}
    size_str = size_str.upper().strip()
    
    for unit, multiplier in units.items():
        if size_str.endswith(unit):
            try:
                number = float(size_str[:-len(unit)])
                return int(number * multiplier)
            except ValueError:
                pass
    
    try:
        return int(size_str)
    except ValueError:
        raise ValueError(f"Invalid size format: {size_str}")


async def compute_file_hash(file_path: Path) -> str:
    """Compute SHA-256 hash of a file"""
    sha256_hash = hashlib.sha256()
    async with aiofiles.open(file_path, 'rb') as f:
        while True:
            chunk = await f.read(8192)
            if not chunk:
                break
            sha256_hash.update(chunk)
    return sha256_hash.hexdigest()


async def send_progress_update(session_id: str, message_type: str, payload: Dict[str, Any]):
    """Send progress update via WebSocket"""
    if session_id in websocket_connections:
        try:
            message = ProgressMessage(
                type=message_type,
                sessionId=session_id,
                payload=payload
            )
            await websocket_connections[session_id].send_json(message.dict())
        except Exception as e:
            logger.error(f"Error sending progress update: {e}")


# ============================================================================
# FastAPI Application
# ============================================================================

app = FastAPI(
    title="ARBOR - Recursive Directory Upload Server",
    description="Browser-based interface for recursive directory uploads with metadata preservation",
    version="1.0.0"
)


# ============================================================================
# HTML/CSS/JS Embedded Frontend
# ============================================================================

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ARBOR - Directory Upload Server</title>
    <style>
        @font-face {
            font-family: 'JetBrains Mono';
            src: url('/fonts/jetbrains-mono/JetBrainsMono-Regular.ttf') format('truetype');
            font-weight: 400;
            font-style: normal;
        }
        
        @font-face {
            font-family: 'JetBrains Mono';
            src: url('/fonts/jetbrains-mono/JetBrainsMono-Bold.ttf') format('truetype');
            font-weight: 700;
            font-style: normal;
        }
        
        @font-face {
            font-family: 'JetBrains Mono';
            src: url('/fonts/jetbrains-mono/JetBrainsMono-Italic.ttf') format('truetype');
            font-weight: 400;
            font-style: italic;
        }
        
        @font-face {
            font-family: 'JetBrains Mono';
            src: url('/fonts/jetbrains-mono/JetBrainsMono-BoldItalic.ttf') format('truetype');
            font-weight: 700;
            font-style: italic;
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        :root {
            --bg-primary: #0d1117;
            --bg-secondary: #161b22;
            --bg-tertiary: #21262d;
            --text-primary: #c9d1d9;
            --text-secondary: #8b949e;
            --border-color: #30363d;
            --accent-color: #238636;
            --accent-hover: #2ea043;
            --error-color: #f85149;
            --warning-color: #d29922;
            --success-color: #3fb950;
        }

        body {
            font-family: 'JetBrains Mono', 'Courier New', monospace;
            background-color: var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.6;
            padding: 20px;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
        }

        header {
            text-align: center;
            margin-bottom: 40px;
            padding: 30px 0;
            border-bottom: 2px solid var(--border-color);
        }

        h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            color: var(--accent-color);
            font-weight: 700;
            letter-spacing: 2px;
        }

        .subtitle {
            color: var(--text-secondary);
            font-size: 0.95em;
            letter-spacing: 0.5px;
        }

        .auth-section {
            background: var(--bg-secondary);
            padding: 30px;
            border-radius: 8px;
            margin-bottom: 30px;
            display: none;
        }

        .auth-section.active {
            display: block;
        }

        .upload-section {
            background: var(--bg-secondary);
            padding: 30px;
            border-radius: 8px;
            margin-bottom: 30px;
            border: 1px solid var(--border-color);
        }

        .drop-zone {
            border: 3px dashed var(--border-color);
            border-radius: 8px;
            padding: 60px 20px;
            text-align: center;
            cursor: pointer;
            transition: all 0.3s ease;
            margin-bottom: 20px;
            background: var(--bg-tertiary);
        }

        .drop-zone:hover, .drop-zone.drag-over {
            border-color: var(--accent-color);
            background-color: var(--bg-primary);
        }

        .drop-zone-text {
            font-size: 1.1em;
            margin-bottom: 15px;
            color: var(--text-primary);
            font-weight: 600;
        }

        .btn {
            background-color: var(--accent-color);
            color: white;
            border: none;
            padding: 12px 30px;
            font-size: 1em;
            border-radius: 5px;
            cursor: pointer;
            transition: background-color 0.3s;
        }

        .btn:hover {
            background-color: var(--accent-hover);
        }

        .btn:disabled {
            background-color: var(--border-color);
            cursor: not-allowed;
        }

        .btn-secondary {
            background-color: var(--bg-tertiary);
            color: var(--text-primary);
        }

        .btn-secondary:hover {
            background-color: var(--border-color);
        }

        .btn-danger {
            background-color: var(--error-color);
        }

        .btn-danger:hover {
            background-color: #d32f2f;
        }

        input[type="file"] {
            display: none;
        }

        input[type="text"], input[type="password"] {
            width: 100%;
            padding: 12px;
            margin-bottom: 15px;
            border: 1px solid var(--border-color);
            border-radius: 5px;
            background-color: var(--bg-primary);
            color: var(--text-primary);
            font-size: 1em;
        }

        .file-preview {
            margin-top: 20px;
            padding: 20px;
            background: var(--bg-primary);
            border-radius: 5px;
            max-height: 400px;
            overflow-y: auto;
        }

        .file-preview h3 {
            margin-bottom: 15px;
        }

        .file-tree {
            font-family: 'JetBrains Mono', 'Courier New', monospace;
            font-size: 0.85em;
        }

        .file-tree-item {
            padding: 5px 0;
            padding-left: 20px;
            color: var(--text-secondary);
        }

        .file-tree-item.directory {
            color: var(--accent-color);
            font-weight: 600;
        }

        .file-tree-item::before {
            content: '├─ ';
            color: var(--border-color);
            margin-right: 5px;
        }

        .file-tree-item.directory::before {
            content: '▸ ';
            color: var(--accent-color);
        }

        .progress-section {
            display: none;
            margin-top: 30px;
        }

        .progress-section.active {
            display: block;
        }

        .progress-bar-container {
            width: 100%;
            height: 30px;
            background-color: var(--bg-tertiary);
            border-radius: 15px;
            overflow: hidden;
            margin-bottom: 20px;
        }

        .progress-bar {
            height: 100%;
            background-color: var(--accent-color);
            transition: width 0.3s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
        }

        .progress-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }

        .progress-item {
            background: var(--bg-primary);
            padding: 15px;
            border-radius: 5px;
        }

        .progress-item-label {
            color: var(--text-secondary);
            font-size: 0.9em;
            margin-bottom: 5px;
        }

        .progress-item-value {
            font-size: 1.2em;
            font-weight: bold;
        }

        .controls {
            display: flex;
            gap: 10px;
            margin-top: 20px;
            flex-wrap: wrap;
        }

        .completion-summary {
            display: none;
            margin-top: 30px;
            padding: 20px;
            background: var(--bg-secondary);
            border-radius: 8px;
        }

        .completion-summary.active {
            display: block;
        }

        .completion-summary h3 {
            margin-bottom: 15px;
            color: var(--accent-color);
        }

        .error-log {
            max-height: 200px;
            overflow-y: auto;
            background: var(--bg-primary);
            padding: 15px;
            border-radius: 5px;
            margin-top: 15px;
        }

        .error-item {
            color: var(--error-color);
            margin-bottom: 5px;
            font-size: 0.9em;
        }

        .file-browser {
            margin-top: 40px;
            padding: 30px;
            background: var(--bg-secondary);
            border-radius: 8px;
        }

        .file-list {
            list-style: none;
            margin-top: 20px;
        }

        .file-list-item {
            padding: 10px;
            background: var(--bg-primary);
            margin-bottom: 5px;
            border-radius: 5px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .file-list-item:hover {
            background: var(--bg-tertiary);
        }

        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }

        .spinner {
            border: 3px solid var(--bg-tertiary);
            border-top: 3px solid var(--accent-color);
            border-radius: 50%;
            width: 20px;
            height: 20px;
            animation: spin 1s linear infinite;
            display: inline-block;
            margin-left: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>ARBOR</h1>
            <p class="subtitle">Recursive Directory Upload Server</p>
        </header>

        <div id="authSection" class="auth-section">
            <h2>Login Required</h2>
            <input type="text" id="username" placeholder="Username">
            <input type="password" id="password" placeholder="Password">
            <button class="btn" onclick="login()">Login</button>
            <div id="authError" style="color: var(--error-color); margin-top: 10px;"></div>
        </div>

        <div id="mainSection" class="upload-section">
            <div class="drop-zone" id="dropZone">
                <div class="drop-zone-text">Drag and drop a directory here</div>
                <p style="margin-bottom: 15px; color: var(--text-secondary);">or</p>
                <button class="btn" onclick="document.getElementById('directoryInput').click()">
                    Select Directory
                </button>
                <input type="file" id="directoryInput" webkitdirectory directory multiple>
            </div>

            <div id="filePreview" class="file-preview" style="display: none;">
                <h3>Selected Files</h3>
                <div id="fileStats"></div>
                <div class="file-tree" id="fileTree"></div>
                <div class="controls">
                    <button class="btn" onclick="startUpload()">Start Upload</button>
                    <button class="btn btn-secondary" onclick="clearSelection()">Clear</button>
                </div>
            </div>

            <div id="progressSection" class="progress-section">
                <h3>Upload Progress</h3>
                <div class="progress-bar-container">
                    <div class="progress-bar" id="progressBar">0%</div>
                </div>
                <div class="progress-info">
                    <div class="progress-item">
                        <div class="progress-item-label">Current File</div>
                        <div class="progress-item-value" id="currentFile">-</div>
                    </div>
                    <div class="progress-item">
                        <div class="progress-item-label">Files Completed</div>
                        <div class="progress-item-value" id="filesCompleted">0 / 0</div>
                    </div>
                    <div class="progress-item">
                        <div class="progress-item-label">Transfer Speed</div>
                        <div class="progress-item-value" id="transferSpeed">0 MB/s</div>
                    </div>
                    <div class="progress-item">
                        <div class="progress-item-label">ETA</div>
                        <div class="progress-item-value" id="eta">-</div>
                    </div>
                </div>
                <div class="controls">
                    <button class="btn btn-secondary" id="pauseBtn" onclick="pauseUpload()">Pause</button>
                    <button class="btn btn-danger" onclick="cancelUpload()">Cancel</button>
                </div>
            </div>

            <div id="completionSummary" class="completion-summary">
                <h3>Upload Complete!</h3>
                <p><strong>Success:</strong> <span id="successCount">0</span> files</p>
                <p><strong>Failed:</strong> <span id="failureCount">0</span> files</p>
                <div id="errorLog" class="error-log" style="display: none;"></div>
                <div style="margin-top: 20px;">
                    <a href="/files" class="btn">Browse All Files</a>
                </div>
            </div>
        </div>

        <div class="file-browser">
            <h2>Quick Access</h2>
            <p style="color: var(--text-secondary); margin-bottom: 15px;">View all uploaded files in the file explorer</p>
            <a href="/files" class="btn">Open File Explorer</a>
        </div>
    </div>

    <script>
        let selectedFiles = [];
        let currentSession = null;
        let ws = null;
        let authToken = null;
        let isPaused = false;
        let isAuthRequired = false;

        // Check if authentication is required
        async function checkAuth() {
            try {
                const response = await fetch('/api/auth/check');
                const data = await response.json();
                isAuthRequired = data.auth_required;
                
                if (isAuthRequired) {
                    document.getElementById('authSection').classList.add('active');
                    document.getElementById('mainSection').style.display = 'none';
                } else {
                    document.getElementById('mainSection').style.display = 'block';
                }
            } catch (error) {
                console.error('Error checking auth:', error);
            }
        }

        async function login() {
            const username = document.getElementById('username').value;
            const password = document.getElementById('password').value;
            const errorDiv = document.getElementById('authError');

            try {
                const response = await fetch('/api/auth/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ username, password })
                });

                if (response.ok) {
                    const data = await response.json();
                    authToken = data.access_token;
                    document.getElementById('authSection').classList.remove('active');
                    document.getElementById('mainSection').style.display = 'block';
                    errorDiv.textContent = '';
                } else {
                    errorDiv.textContent = 'Invalid username or password';
                }
            } catch (error) {
                errorDiv.textContent = 'Login failed: ' + error.message;
            }
        }

        // Directory input handling
        document.getElementById('directoryInput').addEventListener('change', handleFileSelect);

        // Drag and drop handling
        const dropZone = document.getElementById('dropZone');
        
        dropZone.addEventListener('dragover', (e) => {
            e.preventDefault();
            dropZone.classList.add('drag-over');
        });

        dropZone.addEventListener('dragleave', () => {
            dropZone.classList.remove('drag-over');
        });

        dropZone.addEventListener('drop', (e) => {
            e.preventDefault();
            dropZone.classList.remove('drag-over');
            
            const items = e.dataTransfer.items;
            if (items) {
                handleDroppedItems(items);
            }
        });

        async function handleDroppedItems(items) {
            selectedFiles = [];
            for (let i = 0; i < items.length; i++) {
                const item = items[i].webkitGetAsEntry();
                if (item) {
                    await traverseFileTree(item);
                }
            }
            displayFilePreview();
        }

        async function traverseFileTree(item, path = '') {
            if (item.isFile) {
                const file = await new Promise((resolve) => item.file(resolve));
                file.relativePath = path + file.name;
                selectedFiles.push(file);
            } else if (item.isDirectory) {
                const dirReader = item.createReader();
                const entries = await new Promise((resolve) => {
                    dirReader.readEntries(resolve);
                });
                for (const entry of entries) {
                    await traverseFileTree(entry, path + item.name + '/');
                }
            }
        }

        function handleFileSelect(e) {
            const files = Array.from(e.target.files);
            selectedFiles = files.map(file => {
                file.relativePath = file.webkitRelativePath || file.name;
                return file;
            });
            displayFilePreview();
        }

        function displayFilePreview() {
            const preview = document.getElementById('filePreview');
            const stats = document.getElementById('fileStats');
            const tree = document.getElementById('fileTree');

            if (selectedFiles.length === 0) {
                preview.style.display = 'none';
                return;
            }

            preview.style.display = 'block';

            const totalSize = selectedFiles.reduce((sum, file) => sum + file.size, 0);
            const sizeStr = formatBytes(totalSize);

            stats.innerHTML = `<strong>${selectedFiles.length}</strong> files selected (${sizeStr})`;

            // Build file tree
            const fileTreeMap = {};
            selectedFiles.forEach(file => {
                const parts = file.relativePath.split('/');
                let current = fileTreeMap;
                parts.forEach((part, index) => {
                    if (!current[part]) {
                        current[part] = index === parts.length - 1 ? null : {};
                    }
                    if (index < parts.length - 1) {
                        current = current[part];
                    }
                });
            });

            tree.innerHTML = renderFileTree(fileTreeMap);
        }

        function renderFileTree(tree, level = 0) {
            let html = '';
            for (const [name, children] of Object.entries(tree)) {
                const indent = '&nbsp;'.repeat(level * 4);
                if (children === null) {
                    html += `<div class="file-tree-item" style="padding-left: ${level * 20}px">${name}</div>`;
                } else {
                    html += `<div class="file-tree-item directory" style="padding-left: ${level * 20}px">${name}</div>`;
                    html += renderFileTree(children, level + 1);
                }
            }
            return html;
        }

        function clearSelection() {
            selectedFiles = [];
            document.getElementById('directoryInput').value = '';
            document.getElementById('filePreview').style.display = 'none';
        }

        async function startUpload() {
            if (selectedFiles.length === 0) {
                alert('Please select a directory first');
                return;
            }

            try {
                // Initialize upload session
                const headers = { 'Content-Type': 'application/json' };
                if (authToken) {
                    headers['Authorization'] = `Bearer ${authToken}`;
                }

                const initResponse = await fetch('/api/upload/init', {
                    method: 'POST',
                    headers: headers,
                    body: JSON.stringify({
                        total_files: selectedFiles.length,
                        total_bytes: selectedFiles.reduce((sum, f) => sum + f.size, 0)
                    })
                });

                if (!initResponse.ok) {
                    throw new Error('Failed to initialize upload session');
                }

                const { session_id } = await initResponse.json();
                currentSession = session_id;

                // Connect WebSocket
                const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
                const wsUrl = `${wsProtocol}//${window.location.host}/ws/upload/${session_id}`;
                ws = new WebSocket(wsUrl);

                ws.onmessage = handleWebSocketMessage;
                ws.onerror = (error) => console.error('WebSocket error:', error);
                ws.onclose = () => console.log('WebSocket closed');

                // Show progress section
                document.getElementById('progressSection').classList.add('active');
                document.getElementById('filePreview').style.display = 'none';

                // Upload files
                await uploadFiles(session_id);

            } catch (error) {
                console.error('Upload error:', error);
                alert('Upload failed: ' + error.message);
            }
        }

        async function uploadFiles(sessionId) {
            for (let i = 0; i < selectedFiles.length; i++) {
                if (isPaused) {
                    await new Promise(resolve => {
                        const checkPause = setInterval(() => {
                            if (!isPaused) {
                                clearInterval(checkPause);
                                resolve();
                            }
                        }, 100);
                    });
                }

                const file = selectedFiles[i];
                
                try {
                    // Compute checksum
                    const checksum = await computeChecksum(file);
                    
                    // Prepare metadata
                    const metadata = {
                        relativePath: file.relativePath,
                        originalName: file.name,
                        size: file.size,
                        mtime: file.lastModified / 1000,
                        sha256: checksum,
                        compressed: false
                    };

                    // Upload file
                    const formData = new FormData();
                    formData.append('file', file);
                    formData.append('metadata', JSON.stringify(metadata));
                    formData.append('session_id', sessionId);

                    const headers = {};
                    if (authToken) {
                        headers['Authorization'] = `Bearer ${authToken}`;
                    }

                    const response = await fetch('/api/upload/chunk', {
                        method: 'POST',
                        headers: headers,
                        body: formData
                    });

                    if (!response.ok) {
                        throw new Error(`Failed to upload ${file.name}`);
                    }

                } catch (error) {
                    console.error(`Error uploading ${file.name}:`, error);
                }
            }

            // Complete upload
            const headers = { 'Content-Type': 'application/json' };
            if (authToken) {
                headers['Authorization'] = `Bearer ${authToken}`;
            }

            await fetch('/api/upload/complete', {
                method: 'POST',
                headers: headers,
                body: JSON.stringify({ session_id: sessionId })
            });
        }

        async function computeChecksum(file) {
            const buffer = await file.arrayBuffer();
            const hashBuffer = await crypto.subtle.digest('SHA-256', buffer);
            const hashArray = Array.from(new Uint8Array(hashBuffer));
            return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
        }

        function handleWebSocketMessage(event) {
            const message = JSON.parse(event.data);
            const { type, payload } = message;

            if (type === 'progress') {
                updateProgress(payload);
            } else if (type === 'complete') {
                showCompletion(payload);
            } else if (type === 'error') {
                console.error('Upload error:', payload);
            }
        }

        function updateProgress(payload) {
            const {
                currentFile,
                overallProgress,
                filesCompleted,
                filesTotal,
                transferSpeed,
                eta
            } = payload;

            document.getElementById('progressBar').style.width = overallProgress + '%';
            document.getElementById('progressBar').textContent = overallProgress.toFixed(1) + '%';
            document.getElementById('currentFile').textContent = currentFile || '-';
            document.getElementById('filesCompleted').textContent = `${filesCompleted} / ${filesTotal}`;
            document.getElementById('transferSpeed').textContent = formatBytes(transferSpeed) + '/s';
            document.getElementById('eta').textContent = eta ? formatTime(eta) : '-';
        }

        function showCompletion(payload) {
            document.getElementById('progressSection').classList.remove('active');
            const summary = document.getElementById('completionSummary');
            summary.classList.add('active');

            document.getElementById('successCount').textContent = payload.filesCompleted || 0;
            document.getElementById('failureCount').textContent = payload.filesFailed || 0;

            if (payload.errors && payload.errors.length > 0) {
                const errorLog = document.getElementById('errorLog');
                errorLog.style.display = 'block';
                errorLog.innerHTML = payload.errors.map(e => 
                    `<div class="error-item">${e.file}: ${e.error}</div>`
                ).join('');
            }

            if (ws) {
                ws.close();
                ws = null;
            }
        }

        function pauseUpload() {
            isPaused = !isPaused;
            const btn = document.getElementById('pauseBtn');
            btn.textContent = isPaused ? 'Resume' : 'Pause';
        }

        async function cancelUpload() {
            if (!currentSession) return;

            const headers = {};
            if (authToken) {
                headers['Authorization'] = `Bearer ${authToken}`;
            }

            await fetch(`/api/upload/${currentSession}`, {
                method: 'DELETE',
                headers: headers
            });

            if (ws) {
                ws.close();
                ws = null;
            }

            document.getElementById('progressSection').classList.remove('active');
            clearSelection();
        }

        async function loadUploadedFiles() {
            const headers = {};
            if (authToken) {
                headers['Authorization'] = `Bearer ${authToken}`;
            }

            try {
                const response = await fetch('/api/files', { headers });
                const files = await response.json();
                
                const fileList = document.getElementById('fileList');
                fileList.innerHTML = files.map(file => `
                    <li class="file-list-item">
                        <span>${file.path}</span>
                        <button class="btn btn-secondary" onclick="downloadFile('${file.path}')">
                            Download
                        </button>
                    </li>
                `).join('');
            } catch (error) {
                console.error('Error loading files:', error);
            }
        }

        async function downloadFile(path) {
            const headers = {};
            if (authToken) {
                headers['Authorization'] = `Bearer ${authToken}`;
            }

            window.location.href = `/api/files/${encodeURIComponent(path)}`;
        }

        function formatBytes(bytes) {
            if (bytes === 0) return '0 Bytes';
            const k = 1024;
            const sizes = ['Bytes', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + sizes[i];
        }

        function formatTime(seconds) {
            if (seconds < 60) return seconds.toFixed(0) + 's';
            if (seconds < 3600) return (seconds / 60).toFixed(0) + 'm';
            return (seconds / 3600).toFixed(1) + 'h';
        }

        // Initialize on load
        checkAuth();
        loadUploadedFiles();
    </script>
</body>
</html>
"""

FILES_EXPLORER_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>File Explorer - ARBOR</title>
    <style>
        @font-face {
            font-family: 'JetBrains Mono';
            src: url('/fonts/jetbrains-mono/JetBrainsMono-Regular.ttf') format('truetype');
            font-weight: 400;
            font-style: normal;
        }
        
        @font-face {
            font-family: 'JetBrains Mono';
            src: url('/fonts/jetbrains-mono/JetBrainsMono-Bold.ttf') format('truetype');
            font-weight: 700;
            font-style: normal;
        }

        :root {
            --bg-primary: #0d1117;
            --bg-secondary: #161b22;
            --bg-tertiary: #21262d;
            --border-color: #30363d;
            --text-primary: #c9d1d9;
            --text-secondary: #8b949e;
            --accent-color: #58a6ff;
            --success-color: #3fb950;
            --error-color: #f85149;
            --hover-bg: #1f2937;
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'JetBrains Mono', monospace;
            background-color: var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.6;
            padding: 20px;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
        }

        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 1px solid var(--border-color);
        }

        .header h1 {
            color: var(--success-color);
            font-size: 2rem;
        }

        .header-subtitle {
            color: var(--text-secondary);
            font-size: 0.9rem;
        }

        .nav-links {
            display: flex;
            gap: 15px;
        }

        .btn {
            padding: 10px 20px;
            background-color: var(--success-color);
            color: white;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.9rem;
            text-decoration: none;
            display: inline-block;
            transition: all 0.2s;
        }

        .btn:hover {
            opacity: 0.85;
            transform: translateY(-1px);
        }

        .btn-secondary {
            background-color: var(--bg-tertiary);
        }

        .btn-danger {
            background-color: var(--error-color);
        }

        .stats-bar {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }

        .stat-card {
            background-color: var(--bg-secondary);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 20px;
        }

        .stat-label {
            color: var(--text-secondary);
            font-size: 0.85rem;
            margin-bottom: 8px;
        }

        .stat-value {
            color: var(--accent-color);
            font-size: 1.5rem;
            font-weight: 700;
        }

        .toolbar {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
            padding: 15px;
            background-color: var(--bg-secondary);
            border-radius: 8px;
            border: 1px solid var(--border-color);
        }

        .search-box {
            flex: 1;
            max-width: 400px;
            padding: 10px 15px;
            background-color: var(--bg-primary);
            border: 1px solid var(--border-color);
            border-radius: 6px;
            color: var(--text-primary);
            font-family: 'JetBrains Mono', monospace;
        }

        .session-container {
            margin-bottom: 30px;
        }

        .session-header {
            background-color: var(--bg-secondary);
            border: 1px solid var(--border-color);
            border-radius: 8px 8px 0 0;
            padding: 15px 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            cursor: pointer;
            transition: background-color 0.2s;
        }

        .session-header:hover {
            background-color: var(--hover-bg);
        }

        .session-info {
            flex: 1;
        }

        .session-date {
            color: var(--accent-color);
            font-weight: 700;
            font-size: 1.1rem;
            margin-bottom: 5px;
        }

        .session-meta {
            color: var(--text-secondary);
            font-size: 0.85rem;
        }

        .session-actions {
            display: flex;
            gap: 10px;
        }

        .expand-icon {
            margin-left: 15px;
            color: var(--text-secondary);
            transition: transform 0.3s;
        }

        .expand-icon.expanded {
            transform: rotate(90deg);
        }

        .file-grid {
            display: none;
            background-color: var(--bg-tertiary);
            border: 1px solid var(--border-color);
            border-top: none;
            border-radius: 0 0 8px 8px;
            padding: 20px;
        }

        .file-grid.expanded {
            display: block;
        }

        .file-table {
            width: 100%;
            border-collapse: collapse;
        }

        .file-table th {
            text-align: left;
            padding: 12px;
            background-color: var(--bg-secondary);
            color: var(--text-secondary);
            font-weight: 600;
            font-size: 0.85rem;
            border-bottom: 1px solid var(--border-color);
        }

        .file-table td {
            padding: 12px;
            border-bottom: 1px solid var(--border-color);
        }

        .file-table tr:hover {
            background-color: var(--hover-bg);
        }

        .file-icon {
            display: inline-block;
            width: 20px;
            margin-right: 10px;
            text-align: center;
        }

        .file-name {
            color: var(--text-primary);
            font-weight: 500;
        }

        .file-size {
            color: var(--text-secondary);
            font-size: 0.9rem;
        }

        .file-date {
            color: var(--text-secondary);
            font-size: 0.85rem;
        }

        .download-btn {
            padding: 6px 12px;
            background-color: var(--accent-color);
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.8rem;
            text-decoration: none;
            display: inline-block;
        }

        .download-btn:hover {
            opacity: 0.85;
        }

        .empty-state {
            text-align: center;
            padding: 60px 20px;
            color: var(--text-secondary);
        }

        .empty-state-icon {
            font-size: 4rem;
            margin-bottom: 20px;
            opacity: 0.3;
        }

        .loading {
            text-align: center;
            padding: 40px;
            color: var(--text-secondary);
        }

        .spinner {
            border: 3px solid var(--bg-tertiary);
            border-top: 3px solid var(--accent-color);
            border-radius: 50%;
            width: 40px;
            height: 40px;
            animation: spin 1s linear infinite;
            margin: 0 auto 20px;
        }

        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <div class=\"container\">
        <div class=\"header\">
            <div>
                <h1>📁 ARBOR File Explorer</h1>
                <div class=\"header-subtitle\">Browse and download your uploaded files</div>
            </div>
            <div class=\"nav-links\">
                <a href=\"/\" class=\"btn btn-secondary\">← Back to Upload</a>
            </div>
        </div>

        <div class=\"stats-bar\" id=\"statsBar\">
            <div class=\"stat-card\">
                <div class=\"stat-label\">Total Sessions</div>
                <div class=\"stat-value\" id=\"totalSessions\">-</div>
            </div>
            <div class=\"stat-card\">
                <div class=\"stat-label\">Total Files</div>
                <div class=\"stat-value\" id=\"totalFiles\">-</div>
            </div>
            <div class=\"stat-card\">
                <div class=\"stat-label\">Total Size</div>
                <div class=\"stat-value\" id=\"totalSize\">-</div>
            </div>
        </div>

        <div class=\"toolbar\">
            <input type=\"text\" class=\"search-box\" id=\"searchBox\" placeholder=\"Search files...\">
            <button class=\"btn\" onclick=\"loadFiles()\">🔄 Refresh</button>
        </div>

        <div id=\"loadingState\" class=\"loading\">
            <div class=\"spinner\"></div>
            <div>Loading files...</div>
        </div>

        <div id=\"sessionsContainer\"></div>

        <div id=\"emptyState\" class=\"empty-state\" style=\"display: none;\">
            <div class=\"empty-state-icon\">📂</div>
            <h3>No files uploaded yet</h3>
            <p>Upload some directories to see them here</p>
            <a href=\"/\" class=\"btn\" style=\"margin-top: 20px;\">Start Uploading</a>
        </div>
    </div>

    <script>
        let allData = null;

        function formatBytes(bytes) {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
        }

        function formatDate(timestamp) {
            const date = new Date(timestamp * 1000);
            return date.toLocaleString('en-US', {
                year: 'numeric',
                month: 'short',
                day: 'numeric',
                hour: '2-digit',
                minute: '2-digit'
            });
        }

        function getFileIcon(filename) {
            const ext = filename.split('.').pop().toLowerCase();
            const icons = {
                'pdf': '📄',
                'doc': '📝', 'docx': '📝',
                'xls': '📊', 'xlsx': '📊',
                'ppt': '📊', 'pptx': '📊',
                'jpg': '🖼️', 'jpeg': '🖼️', 'png': '🖼️', 'gif': '🖼️', 'bmp': '🖼️',
                'mp4': '🎬', 'avi': '🎬', 'mov': '🎬',
                'mp3': '🎵', 'wav': '🎵', 'flac': '🎵',
                'zip': '📦', 'rar': '📦', 'tar': '📦', 'gz': '📦',
                'txt': '📃', 'md': '📃',
                'py': '🐍', 'js': '📜', 'html': '🌐', 'css': '🎨',
                'json': '{ }', 'xml': '< >', 'yaml': '⚙️', 'yml': '⚙️'
            };
            return icons[ext] || '📄';
        }

        function toggleSession(sessionIndex) {
            const fileGrid = document.getElementById(`session-files-${sessionIndex}`);
            const icon = document.getElementById(`expand-icon-${sessionIndex}`);
            
            fileGrid.classList.toggle('expanded');
            icon.classList.toggle('expanded');
        }

        function downloadFile(filePath) {
            window.location.href = `/api/files/${encodeURIComponent(filePath)}`;
        }

        function downloadSession(sessionName) {
            window.location.href = `/api/files/session/${encodeURIComponent(sessionName)}/archive`;
        }

        async function loadFiles() {
            document.getElementById('loadingState').style.display = 'block';
            document.getElementById('sessionsContainer').innerHTML = '';
            document.getElementById('emptyState').style.display = 'none';

            try {
                const response = await fetch('/api/files');
                allData = await response.json();

                document.getElementById('loadingState').style.display = 'none';

                if (allData.sessions.length === 0) {
                    document.getElementById('emptyState').style.display = 'block';
                    document.getElementById('totalSessions').textContent = '0';
                    document.getElementById('totalFiles').textContent = '0';
                    document.getElementById('totalSize').textContent = '0 B';
                    return;
                }

                // Update stats
                document.getElementById('totalSessions').textContent = allData.sessions.length;
                document.getElementById('totalFiles').textContent = allData.totalFiles;
                document.getElementById('totalSize').textContent = formatBytes(allData.totalSize);

                renderSessions(allData.sessions);
            } catch (error) {
                console.error('Error loading files:', error);
                document.getElementById('loadingState').innerHTML = '<p style=\"color: var(--error-color);\">Error loading files. Please try again.</p>';
            }
        }

        function renderSessions(sessions) {
            const container = document.getElementById('sessionsContainer');
            container.innerHTML = '';

            sessions.forEach((session, index) => {
                const sessionDiv = document.createElement('div');
                sessionDiv.className = 'session-container';
                
                sessionDiv.innerHTML = `
                    <div class=\"session-header\" onclick=\"toggleSession(${index})\">
                        <div class=\"session-info\">
                            <div class=\"session-date\">${formatDate(session.date)}</div>
                            <div class=\"session-meta\">
                                ${session.fileCount} files · ${formatBytes(session.size)}
                            </div>
                        </div>
                        <div class=\"session-actions\" onclick=\"event.stopPropagation();\">
                            <button class=\"btn btn-secondary\" onclick=\"event.stopPropagation(); downloadSession('${session.name}')\">
                                ⬇️ Download Session
                            </button>
                        </div>
                        <span class=\"expand-icon\" id=\"expand-icon-${index}\">▶</span>
                    </div>
                    <div class=\"file-grid\" id=\"session-files-${index}\">
                        <table class=\"file-table\">
                            <thead>
                                <tr>
                                    <th>Name</th>
                                    <th>Size</th>
                                    <th>Modified</th>
                                    <th>Action</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${session.files.map(file => `
                                    <tr>
                                        <td>
                                            <span class=\"file-icon\">${getFileIcon(file.name)}</span>
                                            <span class=\"file-name\">${file.path}</span>
                                        </td>
                                        <td class=\"file-size\">${formatBytes(file.size)}</td>
                                        <td class=\"file-date\">${formatDate(file.mtime)}</td>
                                        <td>
                                            <button class=\"download-btn\" onclick=\"downloadFile('${file.fullPath}')\">
                                                ⬇️ Download
                                            </button>
                                        </td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                `;
                
                container.appendChild(sessionDiv);
            });
        }

        // Search functionality
        document.getElementById('searchBox').addEventListener('input', function(e) {
            const searchTerm = e.target.value.toLowerCase();
            
            if (!allData) return;

            if (searchTerm === '') {
                renderSessions(allData.sessions);
                return;
            }

            const filteredSessions = allData.sessions.map(session => ({
                ...session,
                files: session.files.filter(file => 
                    file.name.toLowerCase().includes(searchTerm) ||
                    file.path.toLowerCase().includes(searchTerm)
                )
            })).filter(session => session.files.length > 0);

            renderSessions(filteredSessions);
        });

        // Load files on page load
        window.addEventListener('load', loadFiles);
    </script>
</body>
</html>
"""


# ============================================================================
# API Endpoints
# ============================================================================

@app.get("/", response_class=HTMLResponse)
async def serve_frontend():
    """Serve the embedded web interface"""
    return HTML_TEMPLATE


@app.get("/files", response_class=HTMLResponse)
async def serve_file_explorer():
    """Serve the file explorer interface"""
    return FILES_EXPLORER_TEMPLATE


@app.get("/fonts/{font_path:path}")
async def serve_font(font_path: str):
    """Serve font files"""
    # Sanitize path to prevent directory traversal
    safe_path = sanitize_path(font_path)
    font_file = Path(__file__).parent / "fonts" / safe_path
    
    # Ensure the resolved path is within the fonts directory
    fonts_dir = Path(__file__).parent / "fonts"
    try:
        font_file = font_file.resolve()
        fonts_dir = fonts_dir.resolve()
        if not str(font_file).startswith(str(fonts_dir)):
            raise HTTPException(status_code=403, detail="Access denied")
    except Exception:
        raise HTTPException(status_code=404, detail="Font file not found")
    
    if not font_file.exists() or not font_file.is_file():
        raise HTTPException(status_code=404, detail="Font file not found")
    
    # Determine media type
    ext = font_file.suffix.lower()
    media_type = {
        '.ttf': 'font/ttf',
        '.otf': 'font/otf',
        '.woff': 'font/woff',
        '.woff2': 'font/woff2'
    }.get(ext, 'application/octet-stream')
    
    return FileResponse(
        path=str(font_file),
        media_type=media_type
    )


@app.get("/api/auth/check")
async def check_auth():
    """Check if authentication is required"""
    return {"auth_required": config.security.auth_enabled}


@app.post("/api/auth/login")
async def login(login_req: LoginRequest):
    """Authenticate user and return JWT token"""
    if not config.security.auth_enabled:
        raise HTTPException(status_code=400, detail="Authentication not enabled")
    
    user = users_db.get(login_req.username)
    if not user or not pwd_context.verify(login_req.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password"
        )
    
    access_token = create_access_token(data={"sub": user.username})
    return {"access_token": access_token, "token_type": "bearer"}


@app.post("/api/auth/logout")
async def logout(username: str = Depends(get_current_user)):
    """Logout user (invalidate token - client-side handling)"""
    return {"message": "Logged out successfully"}


@app.post("/api/upload/init")
async def initialize_upload(
    request: Request,
    username: str = Depends(get_current_user)
):
    """Initialize a new upload session"""
    data = await request.json()
    
    session_id = str(uuid.uuid4())
    session = UploadSession(
        session_id=session_id,
        user_id=username,
        created_at=time.time(),
        total_files=data.get("total_files", 0),
        total_bytes=data.get("total_bytes", 0)
    )
    
    upload_sessions[session_id] = session
    
    # Create user upload directory
    user_dir = Path(config.server.upload_dir) / username / session_id
    user_dir.mkdir(parents=True, exist_ok=True)
    
    logger.info(f"Initialized upload session {session_id} for user {username}")
    
    return {"session_id": session_id}


@app.post("/api/upload/chunk")
async def upload_chunk(
    file: UploadFile = File(...),
    metadata: str = Form(...),
    session_id: str = Form(...),
    username: str = Depends(get_current_user)
):
    """Upload a file chunk with metadata"""
    if session_id not in upload_sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    
    session = upload_sessions[session_id]
    if session.status != "active":
        raise HTTPException(status_code=400, detail="Session not active")
    
    # Parse metadata
    file_meta = FileMetadata(**json.loads(metadata))
    
    # Check file extension
    if not is_extension_allowed(file_meta.originalName):
        raise HTTPException(status_code=400, detail="File extension not allowed")
    
    # Check file size
    if file_meta.size > config.server.max_file_size:
        raise HTTPException(status_code=400, detail="File too large")
    
    # Sanitize path
    safe_path = sanitize_path(file_meta.relativePath)
    file_path = Path(config.server.upload_dir) / username / session_id / safe_path
    file_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Write file
    try:
        async with aiofiles.open(file_path, 'wb') as f:
            content = await file.read()
            await f.write(content)
        
        # Verify checksum
        computed_hash = await compute_file_hash(file_path)
        if computed_hash != file_meta.sha256:
            file_path.unlink()
            raise HTTPException(status_code=400, detail="Checksum mismatch")
        
        # Set file permissions and timestamps
        if file_meta.mode:
            os.chmod(file_path, file_meta.mode)
        
        os.utime(file_path, (file_meta.atime or file_meta.mtime, file_meta.mtime))
        
        # Update session
        session.completed_files += 1
        session.transferred_bytes += file_meta.size
        session.current_file = file_meta.relativePath
        session.files_metadata.append(file_meta)
        
        # Calculate transfer speed and ETA
        elapsed_time = (datetime.now(timezone.utc) - session.start_time).total_seconds()
        transfer_speed = session.transferred_bytes / elapsed_time if elapsed_time > 0 else 0
        remaining_bytes = session.total_bytes - session.transferred_bytes
        eta_seconds = remaining_bytes / transfer_speed if transfer_speed > 0 else 0
        
        # Send progress update
        progress_percent = (session.completed_files / session.total_files * 100) if session.total_files > 0 else 0
        await send_progress_update(session_id, "progress", {
            "currentFile": file_meta.relativePath,
            "overallProgress": progress_percent,
            "filesCompleted": session.completed_files,
            "filesTotal": session.total_files,
            "bytesTransferred": session.transferred_bytes,
            "totalBytes": session.total_bytes,
            "transferSpeed": max(0, transfer_speed),
            "eta": max(0, eta_seconds)
        })
        
        logger.info(f"Uploaded file {file_meta.relativePath} for session {session_id}")
        
        return {"status": "success", "file": file_meta.relativePath}
        
    except Exception as e:
        logger.error(f"Error uploading file {file_meta.relativePath}: {e}")
        session.errors.append({"file": file_meta.relativePath, "error": str(e)})
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/upload/complete")
async def complete_upload(
    request: Request,
    username: str = Depends(get_current_user)
):
    """Finalize upload session"""
    data = await request.json()
    session_id = data.get("session_id")
    
    if session_id not in upload_sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    
    session = upload_sessions[session_id]
    session.status = "completed"
    
    # Send completion message
    await send_progress_update(session_id, "complete", {
        "filesCompleted": session.completed_files,
        "filesTotal": session.total_files,
        "filesFailed": len(session.errors),
        "errors": session.errors
    })
    
    logger.info(f"Completed upload session {session_id}")
    
    # Save manifest
    manifest_path = Path(config.server.upload_dir) / username / session_id / "manifest.json"
    async with aiofiles.open(manifest_path, 'w') as f:
        await f.write(json.dumps({
            "session_id": session_id,
            "user_id": username,
            "created_at": session.created_at,
            "completed_at": time.time(),
            "total_files": session.total_files,
            "completed_files": session.completed_files,
            "total_bytes": session.total_bytes,
            "transferred_bytes": session.transferred_bytes,
            "files": [f.dict() for f in session.files_metadata],
            "errors": session.errors
        }, indent=2))
    
    return {"status": "completed"}


@app.get("/api/upload/status/{session_id}")
async def get_upload_status(
    session_id: str,
    username: str = Depends(get_current_user)
):
    """Get upload session status"""
    if session_id not in upload_sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    
    session = upload_sessions[session_id]
    return session.dict()


@app.delete("/api/upload/{session_id}")
async def cancel_upload(
    session_id: str,
    username: str = Depends(get_current_user)
):
    """Cancel and cleanup upload session"""
    if session_id not in upload_sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    
    session = upload_sessions[session_id]
    session.status = "cancelled"
    
    # Send cancellation message
    await send_progress_update(session_id, "cancel", {"message": "Upload cancelled"})
    
    # Cleanup files (optional)
    upload_dir = Path(config.server.upload_dir) / username / session_id
    if upload_dir.exists():
        shutil.rmtree(upload_dir)
    
    # Remove session
    del upload_sessions[session_id]
    if session_id in websocket_connections:
        del websocket_connections[session_id]
    
    logger.info(f"Cancelled upload session {session_id}")
    
    return {"status": "cancelled"}


@app.get("/api/files")
async def list_files(username: str = Depends(get_current_user)):
    """List uploaded files for the user with directory structure"""
    user_dir = Path(config.server.upload_dir) / username
    if not user_dir.exists():
        return {"sessions": [], "totalFiles": 0, "totalSize": 0}
    
    sessions = []
    total_files = 0
    total_size = 0
    
    for session_dir in user_dir.iterdir():
        if session_dir.is_dir():
            # Read manifest if exists
            manifest_path = session_dir / "manifest.json"
            session_name = session_dir.name
            session_time = session_dir.stat().st_mtime
            
            if manifest_path.exists():
                try:
                    async with aiofiles.open(manifest_path, 'r') as f:
                        manifest = json.loads(await f.read())
                        session_time = manifest.get("completed_at", session_time)
                except:
                    pass
            
            files = []
            session_size = 0
            for file_path in session_dir.rglob("*"):
                if file_path.is_file() and file_path.name != "manifest.json":
                    rel_path = file_path.relative_to(session_dir)
                    file_size = file_path.stat().st_size
                    files.append({
                        "name": file_path.name,
                        "path": str(rel_path),
                        "fullPath": str(file_path.relative_to(user_dir)),
                        "size": file_size,
                        "mtime": file_path.stat().st_mtime,
                        "type": "file"
                    })
                    session_size += file_size
                    total_size += file_size
            
            if files:
                sessions.append({
                    "name": session_name,
                    "date": session_time,
                    "files": files,
                    "fileCount": len(files),
                    "size": session_size
                })
                total_files += len(files)
    
    # Sort sessions by date (newest first)
    sessions.sort(key=lambda x: x["date"], reverse=True)
    
    return {
        "sessions": sessions,
        "totalFiles": total_files,
        "totalSize": total_size
    }


@app.get("/api/files/{file_path:path}")
async def download_file(
    file_path: str,
    username: str = Depends(get_current_user)
):
    """Download a specific file"""
    safe_path = sanitize_path(file_path)
    full_path = Path(config.server.upload_dir) / username / safe_path
    
    if not full_path.exists() or not full_path.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    
    return FileResponse(
        path=str(full_path),
        filename=full_path.name,
        media_type='application/octet-stream'
    )


@app.get("/api/files/session/{session_id}/archive")
async def download_session_archive(
    session_id: str,
    background_tasks: BackgroundTasks,
    username: str = Depends(get_current_user)
):
    """Download an entire upload session as a ZIP archive"""
    safe_session = sanitize_path(session_id)
    user_dir = Path(config.server.upload_dir) / username
    session_dir = user_dir / safe_session

    if not session_dir.exists() or not session_dir.is_dir():
        raise HTTPException(status_code=404, detail="Session not found")

    tmp_path: Optional[Path] = None
    try:
        tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".zip")
        tmp_path = Path(tmp_file.name)
        tmp_file.close()

        with zipfile.ZipFile(tmp_path, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
            for path in session_dir.rglob("*"):
                if path.is_file() and path.name != "manifest.json":
                    arcname = Path(session_dir.name) / path.relative_to(session_dir)
                    zf.write(path, arcname=str(arcname))

        def cleanup(path_str: str):
            try:
                os.remove(path_str)
            except OSError:
                pass

        background_tasks.add_task(cleanup, str(tmp_path))

        return FileResponse(
            path=str(tmp_path),
            filename=f"{session_dir.name}.zip",
            media_type="application/zip",
            background=background_tasks
        )
    except Exception as e:
        if tmp_path and tmp_path.exists():
            tmp_path.unlink(missing_ok=True)
        raise HTTPException(status_code=500, detail=f"Failed to create archive: {e}")


@app.post("/api/gitlab/push")
async def gitlab_push(
    request: Request,
    username: str = Depends(get_current_user)
):
    """Push uploaded files to GitLab repository via SSH"""
    if not config.gitlab.enabled:
        raise HTTPException(status_code=400, detail="GitLab integration not enabled")
    
    data = await request.json()
    session_id = data.get("session_id")
    commit_message = data.get("commit_message", "Upload from ARBOR")
    
    if not session_id:
        raise HTTPException(status_code=400, detail="session_id is required")
    
    if session_id not in upload_sessions:
        raise HTTPException(status_code=404, detail="Session not found")
    
    session = upload_sessions[session_id]
    session_dir = Path(config.server.upload_dir) / username / session_id
    
    if not session_dir.exists():
        raise HTTPException(status_code=404, detail="Session directory not found")
    
    try:
        # Initialize git repository if needed
        git_dir = session_dir / ".git"
        if not git_dir.exists():
            result = await asyncio.create_subprocess_exec(
                "git", "init",
                cwd=str(session_dir),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            if result.returncode != 0:
                raise HTTPException(status_code=500, detail=f"Git init failed: {stderr.decode()}")
            
            # Add remote
            result = await asyncio.create_subprocess_exec(
                "git", "remote", "add", "origin", config.gitlab.repository_url,
                cwd=str(session_dir),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            if result.returncode != 0 and b"already exists" not in stderr:
                raise HTTPException(status_code=500, detail=f"Git remote add failed: {stderr.decode()}")
        
        # Configure SSH if key path is provided
        env = os.environ.copy()
        if config.gitlab.ssh_key_path:
            # Use accept-new for better security than no check
            env["GIT_SSH_COMMAND"] = f"ssh -i {config.gitlab.ssh_key_path} -o StrictHostKeyChecking=accept-new"
        
        # Configure GPG signing if key ID is provided
        if config.gitlab.gpg_key_id:
            result = await asyncio.create_subprocess_exec(
                "git", "config", "user.signingkey", config.gitlab.gpg_key_id,
                cwd=str(session_dir),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            await result.communicate()
            
            result = await asyncio.create_subprocess_exec(
                "git", "config", "commit.gpgsign", "true",
                cwd=str(session_dir),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            await result.communicate()
        
        # Add all files
        result = await asyncio.create_subprocess_exec(
            "git", "add", ".",
            cwd=str(session_dir),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env
        )
        stdout, stderr = await result.communicate()
        if result.returncode != 0:
            raise HTTPException(status_code=500, detail=f"Git add failed: {stderr.decode()}")
        
        # Commit
        result = await asyncio.create_subprocess_exec(
            "git", "commit", "-m", commit_message,
            cwd=str(session_dir),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env
        )
        stdout, stderr = await result.communicate()
        
        # Check if commit failed (but allow "nothing to commit" case)
        if result.returncode != 0 and b"nothing to commit" not in stdout and b"nothing to commit" not in stderr:
            raise HTTPException(status_code=500, detail=f"Git commit failed: {stderr.decode()}")
        
        # Push to GitLab
        result = await asyncio.create_subprocess_exec(
            "git", "push", "-u", "origin", config.gitlab.branch,
            cwd=str(session_dir),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env
        )
        stdout, stderr = await result.communicate()
        
        if result.returncode != 0:
            logger.error(f"Git push failed: {stderr.decode()}")
            raise HTTPException(status_code=500, detail=f"Git push failed: {stderr.decode()}")
        
        logger.info(f"Successfully pushed session {session_id} to GitLab")
        
        return {
            "status": "success",
            "message": "Files pushed to GitLab successfully",
            "session_id": session_id
        }
        
    except Exception as e:
        logger.error(f"Error pushing to GitLab: {e}")
        raise HTTPException(status_code=500, detail=str(e))



@app.websocket("/ws/upload/{session_id}")
async def websocket_endpoint(websocket: WebSocket, session_id: str):
    """WebSocket endpoint for real-time progress updates"""
    await websocket.accept()
    websocket_connections[session_id] = websocket
    
    try:
        while True:
            # Keep connection alive and handle any client messages
            data = await websocket.receive_text()
            message = json.loads(data)
            
            if message.get("type") == "pause":
                if session_id in upload_sessions:
                    upload_sessions[session_id].status = "paused"
            elif message.get("type") == "resume":
                if session_id in upload_sessions:
                    upload_sessions[session_id].status = "active"
            
    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected for session {session_id}")
        if session_id in websocket_connections:
            del websocket_connections[session_id]
    except Exception as e:
        logger.error(f"WebSocket error for session {session_id}: {e}")
        if session_id in websocket_connections:
            del websocket_connections[session_id]


# ============================================================================
# CLI and Main
# ============================================================================

def load_config_from_file(config_file: str) -> AppConfig:
    """Load configuration from YAML file"""
    with open(config_file, 'r') as f:
        config_dict = yaml.safe_load(f)
    return AppConfig(**config_dict)


def main():
    """Main entry point"""
    global config
    
    parser = argparse.ArgumentParser(
        description="ARBOR - Recursive Directory Upload Server"
    )
    parser.add_argument(
        "--config",
        type=str,
        help="Path to configuration file (YAML)"
    )
    parser.add_argument(
        "--host",
        type=str,
        default="127.0.0.1",
        help="Host to bind to (default: 127.0.0.1)"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8196,
        help="Port to bind to (default: 8196)"
    )
    parser.add_argument(
        "--upload-dir",
        type=str,
        default="./uploads",
        help="Directory to store uploads (default: ./uploads)"
    )
    parser.add_argument(
        "--max-file-size",
        type=str,
        default="100MB",
        help="Maximum file size (default: 100MB)"
    )
    parser.add_argument(
        "--max-session-size",
        type=str,
        default="100GB",
        help="Maximum total session size (default: 100GB)"
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=16,
        help="Number of worker threads (default: 16)"
    )
    parser.add_argument(
        "--enable-auth",
        action="store_true",
        help="Enable authentication"
    )
    parser.add_argument(
        "--log-level",
        type=str,
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging level (default: INFO)"
    )
    
    args = parser.parse_args()
    
    # Load configuration
    if args.config:
        config = load_config_from_file(args.config)
    else:
        # Use command line arguments
        config.server.host = args.host
        config.server.port = args.port
        config.server.upload_dir = args.upload_dir
        config.server.max_file_size = parse_size(args.max_file_size)
        config.server.max_session_size = parse_size(args.max_session_size)
        config.server.workers = args.workers
        config.security.auth_enabled = args.enable_auth
        config.logging.level = args.log_level
    
    # Configure logging
    logging.getLogger().setLevel(getattr(logging, config.logging.level))
    
    # Create upload directory
    Path(config.server.upload_dir).mkdir(parents=True, exist_ok=True)
    
    # Log configuration
    logger.info("=" * 60)
    logger.info("ARBOR - Recursive Directory Upload Server")
    logger.info("=" * 60)
    logger.info(f"Host: {config.server.host}")
    logger.info(f"Port: {config.server.port}")
    logger.info(f"Upload Directory: {config.server.upload_dir}")
    logger.info(f"Max File Size: {config.server.max_file_size} bytes")
    logger.info(f"Authentication: {'Enabled' if config.security.auth_enabled else 'Disabled'}")
    logger.info("=" * 60)
    logger.info(f"Server running at http://{config.server.host}:{config.server.port}")
    logger.info("Press Ctrl+C to stop")
    logger.info("=" * 60)
    
    # Run server
    uvicorn.run(
        app,
        host=config.server.host,
        port=config.server.port,
        log_level=config.logging.level.lower()
    )


if __name__ == "__main__":
    main()
