# ARBOR Quick Start Guide

Get started with ARBOR in 5 minutes!

## ## Quick Setup

### 1. Install Python Dependencies

```bash
pip install -r requirements.txt
```

### 2. Start the Server

```bash
python upload_server.py
```

The server will start on `http://127.0.0.1:8196`

### 3. Open Your Browser

Navigate to:
```
http://localhost:8196
```

## 📤 Uploading Files

### Method 1: Drag and Drop
1. Open the web interface
2. Drag a folder from your file explorer
3. Drop it onto the upload zone
4. Click "Start Upload"

### Method 2: Directory Picker
1. Open the web interface
2. Click "Select Directory"
3. Choose a folder in the file picker dialog
4. Click "Start Upload"

## ## Monitoring Progress

Once upload starts, you'll see:
- Current file being uploaded
- Overall progress percentage
- Transfer speed
- Estimated time remaining
- Files completed count

## 🎛️ Configuration

### Quick Configuration

Start with custom settings:
```bash
python upload_server.py \
  --host 127.0.0.1 \
  --port 8080 \
  --upload-dir /path/to/uploads \
  --max-file-size 500MB
```

### Using Config File

1. Copy the example config:
   ```bash
   cp config.example.yaml config.yaml
   ```

2. Edit `config.yaml` with your preferences

3. Start server with config:
   ```bash
   python upload_server.py --config config.yaml
   ```

## ## Security Settings

### Enable Authentication

```bash
python upload_server.py --enable-auth
```

Default credentials:
- Username: `admin`
- Password: `admin`

Note: **Important**: Change default credentials in production!

### Block File Types

Edit `config.yaml`:
```yaml
security:
  blocked_extensions: [".exe", ".bat", ".cmd", ".sh", ".ps1"]
```

### Set File Size Limits

```bash
python upload_server.py --max-file-size 100MB
```

## ## Accessing Uploaded Files

### Via Web Interface
1. Scroll to "Uploaded Files" section
2. Click "Refresh List"
3. Click "Download" on any file

### Via File System
Files are stored in:
```
./uploads/<username>/<session-id>/<original-path>
```

## 🧪 Testing

Run the test suite:
```bash
python test_server.py
```

This will verify:
- Server connectivity
- API endpoints
- File upload functionality
- Checksum verification

## 🔧 Common Commands

### Start Server
```bash
python upload_server.py
```

### Start on Different Port
```bash
python upload_server.py --port 8080
```

### Start with Authentication
```bash
python upload_server.py --enable-auth
```

### Start in Debug Mode
```bash
python upload_server.py --log-level DEBUG
```

### View Help
```bash
python upload_server.py --help
```

## 💡 Tips

1. **Large Files**: Server handles files of any size through chunking
2. **Resume Uploads**: Click "Pause" to pause and "Resume" to continue
3. **Metadata**: All file permissions and timestamps are preserved
4. **Progress**: Real-time updates via WebSocket connection
5. **Security**: Always runs on localhost by default for safety

## 🐛 Troubleshooting

### Server Won't Start
- Check if port is already in use
- Try a different port: `--port 8080`

### Upload Fails
- Check file extension isn't blocked
- Verify file size is within limits
- Review server logs for errors

### Can't Connect
- Ensure server is running
- Try `127.0.0.1` instead of `localhost`
- Check firewall settings

## 📚 More Information

- Full documentation: [README.md](README.md)
- Configuration guide: [config.example.yaml](config.example.yaml)
- Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)

## 🌟 Features at a Glance

* Recursive directory upload  
* Drag & drop interface  
* Real-time progress tracking  
* SHA-256 integrity verification  
* Permission & timestamp preservation  
* Dark/light theme support  
* Optional authentication  
* File browsing & download  
* Zero external frontend dependencies  

---

**Need help?** Open an issue on GitHub!

 Happy uploading with ARBOR!
