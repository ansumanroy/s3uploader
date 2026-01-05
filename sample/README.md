# Sample Multipart Upload Implementation

This sample demonstrates uploading a 2GB MP4 file using 5 presigned URLs. The file is split into 5 parts of approximately 400MB each.

## Configuration

- **File Type**: MP4 (video/mp4)
- **File Size**: ~2GB (2,000,000,000 bytes)
- **Max Parts**: 5
- **Chunk Size**: ~400MB per part
- **Presigned URLs**: Already provided (5 URLs)

## Files

- `index.html` - Sample HTML page with upload interface
- `sample-uploader.js` - Sample uploader implementation
- `README.md` - This file

## Usage

### 1. Open the Sample Page

Open `index.html` in a web browser. Make sure `uploader-presigned.js` is in the parent directory.

### 2. Configure Presigned URLs

The sample page includes a configuration section where you can:
- Enter the upload ID
- Enter the S3 bucket name
- Enter the S3 key (file path)
- Enter the presigned URLs as a JSON array

**Presigned URLs Format**:
```json
[
    {
        "partNumber": 1,
        "url": "https://s3.amazonaws.com/bucket/key?uploadId=...&partNumber=1&..."
    },
    {
        "partNumber": 2,
        "url": "https://s3.amazonaws.com/bucket/key?uploadId=...&partNumber=2&..."
    },
    {
        "partNumber": 3,
        "url": "https://s3.amazonaws.com/bucket/key?uploadId=...&partNumber=3&..."
    },
    {
        "partNumber": 4,
        "url": "https://s3.amazonaws.com/bucket/key?uploadId=...&partNumber=4&..."
    },
    {
        "partNumber": 5,
        "url": "https://s3.amazonaws.com/bucket/key?uploadId=...&partNumber=5&..."
    }
]
```

### 3. Load Presigned URLs

Click the "Load Presigned URLs" button to load the configuration.

### 4. Select File

Select an MP4 file (approximately 2GB) to upload.

### 5. Upload

Click the "Upload File" button to start the upload.

## How It Works

1. **Initialize Uploader**: The uploader is initialized with presigned URLs using `S3MultipartUploaderDirectPresigned`
2. **Split File**: The file is split into 5 parts of approximately 400MB each
3. **Upload Parts**: Each part is uploaded to S3 using its corresponding presigned URL
4. **Track Progress**: Progress is tracked and displayed in real-time
5. **Complete Upload**: After all parts are uploaded, the multipart upload is completed

## Implementation Details

### Chunk Size Calculation

For a 2GB file with 5 parts:
```
Chunk Size = File Size / Number of Parts
Chunk Size = 2,000,000,000 bytes / 5
Chunk Size = 400,000,000 bytes (400MB)
```

### Part Upload Order

Parts are uploaded in parallel (5 parts at a time) for faster uploads. The uploader uses the `S3MultipartUploaderDirectPresigned` class which:
- Uploads parts concurrently
- Retries failed parts
- Tracks progress
- Handles errors

### Complete Endpoint

After all parts are uploaded, the uploader calls the complete endpoint to finalize the multipart upload:

```javascript
POST /api/complete-upload
{
    "uploadId": "abc123...",
    "parts": [
        {
            "PartNumber": 1,
            "ETag": "etag1"
        },
        {
            "PartNumber": 2,
            "ETag": "etag2"
        },
        ...
    ]
}
```

## Sample Presigned URLs

The sample includes placeholder presigned URLs. Replace them with your actual presigned URLs:

```javascript
const SAMPLE_PRESIGNED_URLS = {
    uploadId: 'your-upload-id',
    bucket: 'your-bucket-name',
    key: 'uploads/video.mp4',
    presignedUrls: [
        {
            partNumber: 1,
            url: 'https://s3.amazonaws.com/your-bucket/uploads/video.mp4?uploadId=...&partNumber=1&...'
        },
        // ... more URLs
    ]
};
```

## Testing

### Test with Sample Data

1. Open `index.html` in a browser
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

## Customization

### Change Chunk Size

Update the chunk size in `sample-uploader.js`:

```javascript
this.uploader = new S3MultipartUploaderDirectPresigned({
    chunkSize: 400 * 1024 * 1024, // 400MB per part
    maxRetries: 3,
    completeEndpoint: '/api/complete-upload',
    abortEndpoint: '/api/abort-upload'
});
```

### Change Number of Parts

Update the presigned URLs array to include the desired number of parts.

### Change File Type

Update the file input accept attribute in `index.html`:

```html
<input type="file" id="fileInput" class="file-input" accept="video/mp4">
```

## Integration

To integrate this sample into your application:

1. Copy `sample-uploader.js` to your project
2. Include `uploader-presigned.js` in your HTML
3. Update the complete and abort endpoints
4. Configure presigned URLs from your API
5. Customize the UI as needed

## License

MIT

