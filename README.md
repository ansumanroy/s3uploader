# S3 Multipart Upload Application

A JavaScript/HTML application for uploading large files (2GB+) to Amazon S3 using multipart uploads with presigned URLs.

## Features

- ✅ Multipart upload support for large files (2GB+)
- ✅ Progress tracking with visual progress bar
- ✅ Drag and drop file upload
- ✅ Retry logic for failed parts
- ✅ Concurrent part uploads (5 parts at a time)
- ✅ Clean, modern UI
- ✅ Error handling and abort functionality
- ✅ Two upload strategies: on-demand presigned URLs or pre-generated presigned URLs

## Upload Strategies

This project provides two different upload strategies:

### 1. On-Demand Presigned URLs (`uploader.js`)
- Requests presigned URLs from Lambda function as needed
- More API calls but flexible
- Good for dynamic scenarios
- Files: `uploader.js`, `index.html`, `lambda-example.js`

### 2. Pre-Generated Presigned URLs (`uploader-presigned.js`)
- Gets all presigned URLs upfront in a single API call
- Fewer API calls, faster upload start
- Better for predictable uploads
- Files: `uploader-presigned.js`, `index-presigned.html`, `lambda-presigned-example.js`

## How It Works

### Multipart Upload Flow

1. **Initiate Upload**: Request presigned URL to initiate multipart upload
2. **Upload Parts**: Split file into chunks (5MB each) and upload each part concurrently
3. **Complete Upload**: Send all part numbers and ETags to complete the upload

### Lambda Function API

The application expects a Lambda function endpoint that handles the following operations:

#### 1. Initiate Multipart Upload

**Request:**
```json
POST /api/presigned-url
{
  "operation": "initiate",
  "fileName": "large-file.zip",
  "fileType": "application/zip",
  "bucket": "your-bucket",
  "key": "uploads/large-file.zip"
}
```

**Response:**
```json
{
  "uploadId": "abc123...",
  "bucket": "your-bucket",
  "key": "uploads/large-file.zip"
}
```

#### 2. Get Presigned URL for Part Upload

**Request:**
```json
POST /api/presigned-url
{
  "operation": "upload",
  "uploadId": "abc123...",
  "partNumber": 1,
  "bucket": "your-bucket",
  "key": "uploads/large-file.zip"
}
```

**Response:**
```json
{
  "url": "https://s3.amazonaws.com/bucket/key?uploadId=...&partNumber=1&..."
}
```

#### 3. Complete Multipart Upload

**Request:**
```json
POST /api/presigned-url
{
  "operation": "complete",
  "uploadId": "abc123...",
  "parts": [
    {"PartNumber": 1, "ETag": "etag1"},
    {"PartNumber": 2, "ETag": "etag2"},
    ...
  ],
  "bucket": "your-bucket",
  "key": "uploads/large-file.zip"
}
```

**Response:**
```json
{
  "location": "https://s3.amazonaws.com/bucket/key",
  "bucket": "your-bucket",
  "key": "uploads/large-file.zip",
  "etag": "final-etag"
}
```

#### 4. Abort Multipart Upload

**Request:**
```json
POST /api/presigned-url
{
  "operation": "abort",
  "uploadId": "abc123...",
  "bucket": "your-bucket",
  "key": "uploads/large-file.zip"
}
```

## Lambda Function Example

A complete Lambda function example is provided in `lambda-example.js`. Here's a summary of the implementation:

See `lambda-example.js` for the complete implementation. Key features:

- ✅ CORS support for browser requests
- ✅ Presigned URL generation for secure uploads
- ✅ Error handling and validation
- ✅ Support for all multipart upload operations
- ✅ Configurable S3 bucket via environment variable
- ✅ Proper IAM permissions documentation

## Configuration

### 1. Update API Endpoint

Update the API endpoint in `uploader.js` to point to your Lambda function:

```javascript
// In uploader.js, update the UploadUI constructor
this.uploader = new S3MultipartUploader({
    apiEndpoint: 'https://your-api-gateway-url.amazonaws.com/prod/presigned-url', // Your Lambda/API Gateway URL
    chunkSize: 5 * 1024 * 1024, // 5MB chunks (minimum for S3)
    maxRetries: 3
});
```

Or if using a relative path with a proxy:

```javascript
apiEndpoint: '/api/presigned-url' // Proxy to your Lambda function
```

### 2. Deploy Lambda Function

1. Create a new Lambda function in AWS
2. Copy the code from `lambda-example.js`
3. Set environment variable `S3_BUCKET` to your S3 bucket name
4. Configure IAM role with S3 permissions (see IAM permissions below)
5. Create API Gateway endpoint and connect to Lambda
6. Enable CORS on API Gateway

### 3. IAM Permissions

Your Lambda function needs the following IAM permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateMultipartUpload",
        "s3:UploadPart",
        "s3:CompleteMultipartUpload",
        "s3:AbortMultipartUpload",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::your-bucket-name/*"
    }
  ]
}
```

## Usage

1. Open `index.html` in a web browser
2. Select or drag and drop a file
3. Click "Upload File"
4. Monitor the progress bar

## Features Explained

### Chunk Size
- Default: 5MB (minimum for S3 multipart upload)
- Can be increased for better performance with very large files
- Larger chunks = fewer API calls but slower retry on failure

### Concurrent Uploads
- Default: 5 parts uploaded simultaneously
- Can be adjusted in the `upload()` method
- More concurrent uploads = faster but more network load

### Retry Logic
- Each part is retried up to 3 times on failure
- Exponential backoff between retries
- Upload is aborted if all retries fail

## CORS Configuration

If your Lambda function is behind an API Gateway, ensure CORS is enabled:

```json
{
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type"
}
```

## Browser Support

- Chrome/Edge (latest)
- Firefox (latest)
- Safari (latest)
- Requires modern JavaScript (ES6+)

## Security Considerations

1. **Presigned URLs**: Presigned URLs expire after a set time (default 1 hour). Adjust expiration in your Lambda function.
2. **CORS**: Configure CORS properly on your API Gateway/Lambda function.
3. **Authentication**: Add authentication to your Lambda function if needed.
4. **File Validation**: Add file type and size validation in your Lambda function.

## Troubleshooting

### Upload fails immediately
- Check Lambda function URL is correct
- Verify CORS is configured
- Check browser console for errors

### Parts fail to upload
- Verify presigned URL expiration time
- Check S3 bucket permissions
- Verify part numbers are sequential (1, 2, 3, ...)

### Upload hangs
- Check network connectivity
- Verify Lambda function timeout is sufficient
- Check browser console for errors

## Pre-Generated Presigned URLs Approach

If you already have presigned URLs available, use `uploader-presigned.js`. This approach is more efficient as it generates all presigned URLs upfront.

### API Endpoint: Initiate Upload

**Request:**
```json
POST /api/initiate-upload
{
  "fileName": "large-file.zip",
  "fileSize": 2147483648,
  "fileType": "application/zip",
  "totalParts": 410
}
```

**Response:**
```json
{
  "uploadId": "abc123...",
  "bucket": "your-bucket",
  "key": "uploads/large-file.zip",
  "presignedUrls": [
    {
      "partNumber": 1,
      "url": "https://s3.amazonaws.com/bucket/key?uploadId=...&partNumber=1&..."
    },
    {
      "partNumber": 2,
      "url": "https://s3.amazonaws.com/bucket/key?uploadId=...&partNumber=2&..."
    },
    ...
  ]
}
```

### Usage Example

#### Option 1: API Returns Presigned URLs

```javascript
const uploader = new S3MultipartUploaderPresigned({
    apiEndpoint: '/api/initiate-upload',
    chunkSize: 5 * 1024 * 1024,
    maxRetries: 3
});

await uploader.upload(file, (progress) => {
    console.log(`Progress: ${progress.progress}%`);
});
```

#### Option 2: You Already Have Presigned URLs

```javascript
const uploader = new S3MultipartUploaderDirectPresigned({
    chunkSize: 5 * 1024 * 1024,
    maxRetries: 3,
    completeEndpoint: '/api/complete-upload',
    abortEndpoint: '/api/abort-upload'
});

// Initialize with presigned URLs
uploader.initialize({
    uploadId: 'abc123...',
    bucket: 'your-bucket',
    key: 'uploads/file.zip',
    presignedUrls: [
        { partNumber: 1, url: 'https://...' },
        { partNumber: 2, url: 'https://...' },
        ...
    ]
});

await uploader.upload(file, (progress) => {
    console.log(`Progress: ${progress.progress}%`);
});
```

### Lambda Function for Presigned URLs

See `lambda-presigned-example.js` for a complete implementation that generates all presigned URLs upfront.

**Key Differences:**
- Generates all presigned URLs in a single API call
- More efficient for large files
- Requires knowing total parts upfront
- Less flexible but faster

## Comparison: On-Demand vs Pre-Generated Presigned URLs

| Feature | On-Demand (`uploader.js`) | Pre-Generated (`uploader-presigned.js`) |
|---------|---------------------------|-----------------------------------------|
| API Calls | 1 + N (initiate + each part) | 1 (initiate with all URLs) |
| Upload Start | Slower (requests URLs per part) | Faster (all URLs ready) |
| Flexibility | High (can adjust per part) | Lower (must know total parts) |
| Use Case | Dynamic uploads | Predictable uploads |
| Complexity | Lower | Higher (must generate all URLs) |

## License

MIT

