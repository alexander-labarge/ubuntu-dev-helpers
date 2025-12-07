#!/usr/bin/env python3
"""
Simple test script to verify ARBOR server functionality
"""

import requests
import json
import time
import hashlib
from pathlib import Path

def compute_sha256(file_path):
    """Compute SHA-256 hash of a file"""
    sha256_hash = hashlib.sha256()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b""):
            sha256_hash.update(chunk)
    return sha256_hash.hexdigest()

def test_server(base_url="http://127.0.0.1:8196"):
    """Test basic server functionality"""
    print("ARBOR Server Test Suite")
    print("=" * 60)
    
    # Test 1: Check if server is running
    print("\n1. Testing server connection...")
    try:
        response = requests.get(f"{base_url}/")
        assert response.status_code == 200
        print("   [PASS] Server is running")
    except Exception as e:
        print(f"   [FAIL] Server connection failed: {e}")
        return False
    
    # Test 2: Check auth endpoint
    print("\n2. Testing authentication check...")
    try:
        response = requests.get(f"{base_url}/api/auth/check")
        data = response.json()
        print(f"   [PASS] Auth required: {data['auth_required']}")
    except Exception as e:
        print(f"   [FAIL] Auth check failed: {e}")
        return False
    
    # Test 3: Initialize upload session
    print("\n3. Testing upload session initialization...")
    try:
        response = requests.post(
            f"{base_url}/api/upload/init",
            json={"total_files": 1, "total_bytes": 100}
        )
        data = response.json()
        session_id = data['session_id']
        print(f"   [PASS] Session created: {session_id}")
    except Exception as e:
        print(f"   [FAIL] Session initialization failed: {e}")
        return False
    
    # Test 4: Create a test file and upload it
    print("\n4. Testing file upload...")
    try:
        # Create test file
        test_file = Path("/tmp/test_upload_file.txt")
        test_file.write_text("Hello from ARBOR test!")
        
        # Compute checksum
        checksum = compute_sha256(test_file)
        
        # Prepare metadata
        metadata = {
            "relativePath": "test_upload_file.txt",
            "originalName": "test_upload_file.txt",
            "size": test_file.stat().st_size,
            "mtime": test_file.stat().st_mtime,
            "sha256": checksum,
            "compressed": False
        }
        
        # Upload file
        with open(test_file, 'rb') as f:
            files = {'file': f}
            data = {
                'metadata': json.dumps(metadata),
                'session_id': session_id
            }
            response = requests.post(
                f"{base_url}/api/upload/chunk",
                files=files,
                data=data
            )
        
        assert response.status_code == 200
        print(f"   [PASS] File uploaded successfully")
        
        # Clean up test file
        test_file.unlink()
    except Exception as e:
        print(f"   [FAIL] File upload failed: {e}")
        return False
    
    # Test 5: Complete upload session
    print("\n5. Testing upload completion...")
    try:
        response = requests.post(
            f"{base_url}/api/upload/complete",
            json={"session_id": session_id}
        )
        assert response.status_code == 200
        print(f"   [PASS] Upload session completed")
    except Exception as e:
        print(f"   [FAIL] Upload completion failed: {e}")
        return False
    
    # Test 6: List uploaded files
    print("\n6. Testing file listing...")
    try:
        response = requests.get(f"{base_url}/api/files")
        files = response.json()
        print(f"   [PASS] Found {len(files)} uploaded file(s)")
        if files:
            for file in files[:3]:  # Show first 3 files
                print(f"     - {file['path']}")
    except Exception as e:
        print(f"   [FAIL] File listing failed: {e}")
        return False
    
    print("\n" + "=" * 60)
    print("[SUCCESS] All tests passed!")
    print("=" * 60)
    return True

if __name__ == "__main__":
    import sys
    
    # Check if server URL is provided
    base_url = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8196"
    
    success = test_server(base_url)
    sys.exit(0 if success else 1)
