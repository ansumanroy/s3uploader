# Quick Start Guide

This guide will help you quickly test the sample multipart upload implementation for a 2GB MP4 file with 5 presigned URLs.

## Prerequisites

1. A web browser (Chrome, Firefox, Safari, Edge)
2. A local web server (or open directly in browser)
3. 5 presigned URLs for multipart upload (or use the sample configuration)

## Quick Start

### Option 1: Using a Local Web Server

1. **Start a local web server** in the project root:
   ```bash
   # Using Python 3
   python3 -m http.server 8000
   
   # Using Node.js (http-server)
   npx http-server -p 8000
   
   # Using PHP
   php -S localhost:8000
   ```

2. **Open the sample page** in your browser:
   ```
   http://localhost:8000/sample/index.html
   ```

3. **Configure presigned URLs**:
   - Enter your upload ID
   - Enter your S3 bucket name
   - Enter your S3 key (file path)
   - Paste your 5 presigned URLs as JSON array
   - Click "Load Presigned URLs"

4. **Select an MP4 file** (approximately 2GB)

5. **Click "Upload File"** to start the upload

### Option 2: Open Directly in Browser

1. **Open `sample/index.html`** directly in your browser
   - Note: Some browsers may block local file access due to CORS

2. **Configure presigned URLs** as described above

3. **Select and upload** your MP4 file

## Sample Configuration

The sample includes placeholder presigned URLs. Replace them with your actual presigned URLs:

```json
{
  "uploadId": "your-upload-id",
  "bucket": "your-bucket-name",
  "key": "uploads/video.mp4",
  "presignedUrls": [
    {
      "partNumber": 1,
      "url": "https://s3.amazonaws.com/your-bucket/uploads/video.mp4?uploadId=...&partNumber=1&..."
    },
    {
      "partNumber": 2,
      "url": "https://s3.amazonaws.com/your-bucket/uploads/video.mp4?uploadId=...&partNumber=2&..."
    },
    {
      "partNumber": 3,
      "url": "https://s3.amazonaws.com/your-bucket/uploads/video.mp4?uploadId=...&partNumber=3&..."
    },
    {
      "partNumber": 4,
      "url": "https://s3.amazonaws.com/your-bucket/uploads/video.mp4?uploadId=...&partNumber=4&..."
    },
    {
      "partNumber": 5,
      "url": "https://s3.amazonaws.com/your-bucket/uploads/video.mp4?uploadId=...&partNumber=5&..."
    }
  ]
}
```

## How It Works

1. **Initialize**: The uploader is initialized with 5 presigned URLs
2. **Split File**: The 2GB file is split into 5 parts (~400MB each)
3. **Upload Parts**: Each part is uploaded to S3 using its presigned URL
4. **Track Progress**: Progress is displayed in real-time
5. **Complete**: After all parts are uploaded, the multipart upload is completed

## File Structure

```
sample/
├── index.html                 # Sample HTML page
├── sample-uploader.js         # Sample uploader implementation
├── presigned-urls-example.json # Example presigned URLs configuration
├── README.md                  # Detailed documentation
└── QUICKSTART.md             # This file
```

## Configuration

### Chunk Size

The chunk size is calculated automatically based on file size and number of parts:

```
Chunk Size = File Size / Number of Parts
Chunk Size = 2GB / 5 = 400MB per part
```

### Number of Parts

The sample is configured for 5 parts. You can change this by:
1. Providing different number of presigned URLs
2. The chunk size will be automatically adjusted

### Complete Endpoint

Update the complete endpoint in `sample-uploader.js`:

```javascript
this.uploader = new S3MultipartUploaderDirectPresigned({
    chunkSize: 400 * 1024 * 1024,
    maxRetries: 3,
    completeEndpoint: 'https://your-api.com/complete-upload', // Update this
    abortEndpoint: 'https://your-api.com/abort-upload' // Update this
});
```

## Testing

### Test with Sample Data

1. Open `sample/index.html`
2. Load the sample presigned URLs (or configure your own)
3. Select a test MP4 file
4. Click "Upload File"
5. Monitor the progress

### Test with Real Presigned URLs

1. Generate presigned URLs using your Lambda function or API
2. Enter the presigned URLs in the configuration section
3. Click "Load Presigned URLs"
4. Select your MP4 file
5. Click "Upload File"

## Troubleshooting

### Presigned URLs Not Loading

- Check that the JSON format is correct
- Verify that all required fields are present (partNumber, url)
- Check browser console for errors

### Upload Fails

- Verify presigned URLs are valid and not expired
- Check that the file size matches the expected size
- Verify the complete endpoint is accessible
- Check browser console for errors

### Parts Not Uploading

- Verify presigned URLs are correct
- Check S3 bucket permissions
- Verify presigned URL expiration time
- Check network connectivity

## Next Steps

1. **Customize the UI**: Modify `index.html` to match your design
2. **Integrate with your API**: Update the complete and abort endpoints
3. **Add authentication**: Add authentication to your API endpoints
4. **Add error handling**: Enhance error handling for production use
5. **Add progress persistence**: Save upload progress for resumable uploads

## Support

For issues or questions:
1. Check the browser console for errors
2. Verify presigned URLs are valid
3. Check S3 bucket permissions
4. Review the README.md for detailed documentation

## License

MIT

