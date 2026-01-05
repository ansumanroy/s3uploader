/**
 * AWS Lambda Function Example for S3 Multipart Upload
 * 
 * This is an example Lambda function that handles S3 multipart upload operations
 * using presigned URLs. Deploy this to AWS Lambda and configure it with proper
 * IAM permissions and API Gateway.
 * 
 * Required IAM Permissions:
 * - s3:CreateMultipartUpload
 * - s3:UploadPart
 * - s3:CompleteMultipartUpload
 * - s3:AbortMultipartUpload
 * - s3:PutObject (if using presigned URLs)
 */

const AWS = require('aws-sdk');
const s3 = new AWS.S3();

// Configure S3 client
const S3_BUCKET = process.env.S3_BUCKET || 'your-bucket-name';
const PRESIGNED_URL_EXPIRY = 3600; // 1 hour in seconds

/**
 * Generate presigned URL for S3 operation
 */
function generatePresignedUrl(operation, params) {
    return s3.getSignedUrlPromise(operation, {
        ...params,
        Expires: PRESIGNED_URL_EXPIRY
    });
}

/**
 * Lambda handler
 */
exports.handler = async (event) => {
    // Handle CORS preflight
    if (event.httpMethod === 'OPTIONS') {
        return {
            statusCode: 200,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '86400'
            },
            body: ''
        };
    }

    // Parse request body
    let body;
    try {
        body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
    } catch (error) {
        return {
            statusCode: 400,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ error: 'Invalid JSON in request body' })
        };
    }

    const { operation, uploadId, partNumber, parts, fileName, fileType, bucket, key } = body;

    // Validate operation
    if (!operation) {
        return {
            statusCode: 400,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ error: 'Operation is required' })
        };
    }

    const Bucket = bucket || S3_BUCKET;
    const Key = key || `uploads/${fileName || Date.now().toString()}`;

    // CORS headers
    const corsHeaders = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    };

    try {
        switch (operation) {
            case 'initiate':
                return await handleInitiate(Bucket, Key, fileType, corsHeaders);

            case 'upload':
                return await handleUpload(Bucket, Key, uploadId, partNumber, corsHeaders);

            case 'complete':
                return await handleComplete(Bucket, Key, uploadId, parts, corsHeaders);

            case 'abort':
                return await handleAbort(Bucket, Key, uploadId, corsHeaders);

            default:
                return {
                    statusCode: 400,
                    headers: corsHeaders,
                    body: JSON.stringify({ error: `Unknown operation: ${operation}` })
                };
        }
    } catch (error) {
        console.error('Error processing request:', error);
        return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({ error: error.message || 'Internal server error' })
        };
    }
};

/**
 * Handle initiate multipart upload
 */
async function handleInitiate(Bucket, Key, fileType, corsHeaders) {
    const params = {
        Bucket,
        Key,
        ContentType: fileType || 'application/octet-stream'
    };

    try {
        const { UploadId } = await s3.createMultipartUpload(params).promise();

        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({
                uploadId: UploadId,
                bucket: Bucket,
                key: Key
            })
        };
    } catch (error) {
        console.error('Error initiating upload:', error);
        throw error;
    }
}

/**
 * Handle get presigned URL for part upload
 */
async function handleUpload(Bucket, Key, uploadId, partNumber, corsHeaders) {
    if (!uploadId || !partNumber) {
        return {
            statusCode: 400,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'uploadId and partNumber are required' })
        };
    }

    const params = {
        Bucket,
        Key,
        PartNumber: partNumber,
        UploadId: uploadId
    };

    try {
        const presignedUrl = await generatePresignedUrl('uploadPart', params);

        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({
                url: presignedUrl
            })
        };
    } catch (error) {
        console.error('Error generating presigned URL for upload:', error);
        throw error;
    }
}

/**
 * Handle complete multipart upload
 */
async function handleComplete(Bucket, Key, uploadId, parts, corsHeaders) {
    if (!uploadId || !parts || !Array.isArray(parts) || parts.length === 0) {
        return {
            statusCode: 400,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'uploadId and parts array are required' })
        };
    }

    // Sort parts by PartNumber
    const sortedParts = parts.sort((a, b) => a.PartNumber - b.PartNumber);

    // Validate parts
    for (let i = 0; i < sortedParts.length; i++) {
        if (!sortedParts[i].PartNumber || !sortedParts[i].ETag) {
            return {
                statusCode: 400,
                headers: corsHeaders,
                body: JSON.stringify({ error: `Invalid part at index ${i}: PartNumber and ETag are required` })
            };
        }
    }

    const params = {
        Bucket,
        Key,
        UploadId: uploadId,
        MultipartUpload: {
            Parts: sortedParts.map(part => ({
                PartNumber: part.PartNumber,
                ETag: part.ETag
            }))
        }
    };

    try {
        const result = await s3.completeMultipartUpload(params).promise();

        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({
                location: result.Location,
                bucket: result.Bucket,
                key: result.Key,
                etag: result.ETag
            })
        };
    } catch (error) {
        console.error('Error completing upload:', error);
        throw error;
    }
}

/**
 * Handle abort multipart upload
 */
async function handleAbort(Bucket, Key, uploadId, corsHeaders) {
    if (!uploadId) {
        return {
            statusCode: 400,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'uploadId is required' })
        };
    }

    const params = {
        Bucket,
        Key,
        UploadId: uploadId
    };

    try {
        await s3.abortMultipartUpload(params).promise();

        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({ message: 'Upload aborted successfully' })
        };
    } catch (error) {
        console.error('Error aborting upload:', error);
        // Don't throw - abort is best effort
        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({ message: 'Abort request processed' })
        };
    }
}

