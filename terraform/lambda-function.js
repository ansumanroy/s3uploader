/**
 * AWS Lambda Function for S3 Multipart Upload with Presigned URLs
 * 
 * This Lambda function generates all presigned URLs upfront for faster uploads.
 * It's designed to work with API Gateway HTTP API v2 and the S3MultipartUploaderPresigned class.
 * 
 * Required IAM Permissions:
 * - s3:CreateMultipartUpload
 * - s3:UploadPart
 * - s3:CompleteMultipartUpload
 * - s3:AbortMultipartUpload
 * - s3:PutObject (for presigned URLs)
 */

const AWS = require('aws-sdk');
const s3 = new AWS.S3();

// Configure S3 client
const S3_BUCKET = process.env.S3_BUCKET || 'your-bucket-name';
const PRESIGNED_URL_EXPIRY = parseInt(process.env.PRESIGNED_URL_EXPIRY || '3600', 10);

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
 * Lambda handler for API Gateway HTTP API v2
 */
exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event, null, 2));

    // Extract route and method from API Gateway HTTP API v2 event
    // HTTP API v2 uses rawPath and requestContext.http.method
    const route = event.rawPath || event.requestContext?.http?.path || event.path || '';
    const method = event.requestContext?.http?.method || event.requestContext?.httpMethod || event.httpMethod || 'POST';
    
    console.log(`Route: ${route}, Method: ${method}`);
    console.log(`Request Context:`, JSON.stringify(event.requestContext, null, 2));

    // Handle CORS preflight
    if (method === 'OPTIONS') {
        return {
            statusCode: 200,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization',
                'Access-Control-Max-Age': '86400'
            },
            body: ''
        };
    }

    // Parse request body
    let body;
    try {
        body = event.body ? JSON.parse(event.body) : {};
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

    // Determine operation from route
    let operation;
    if (route.includes('initiate-upload')) {
        operation = 'initiate';
    } else if (route.includes('complete-upload')) {
        operation = 'complete';
    } else if (route.includes('abort-upload')) {
        operation = 'abort';
    } else {
        operation = body.operation;
    }

    const { uploadId, parts, fileName, fileSize, fileType, totalParts, bucket, key } = body;

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
                return await handleInitiate(Bucket, Key, fileName, fileSize, fileType, totalParts, corsHeaders);

            case 'complete':
                return await handleComplete(Bucket, Key, uploadId, parts, corsHeaders);

            case 'abort':
                return await handleAbort(Bucket, Key, uploadId, corsHeaders);

            default:
                return {
                    statusCode: 400,
                    headers: corsHeaders,
                    body: JSON.stringify({ error: `Unknown operation: ${operation}. Route: ${route}` })
                };
        }
    } catch (error) {
        console.error('Error processing request:', error);
        return {
            statusCode: 500,
            headers: corsHeaders,
            body: JSON.stringify({ 
                error: error.message || 'Internal server error',
                details: process.env.NODE_ENV === 'dev' ? error.stack : undefined
            })
        };
    }
};

/**
 * Handle initiate multipart upload and generate all presigned URLs
 */
async function handleInitiate(Bucket, Key, fileName, fileSize, fileType, totalParts, corsHeaders) {
    if (!totalParts || totalParts < 1) {
        return {
            statusCode: 400,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'totalParts is required and must be greater than 0' })
        };
    }

    if (!fileSize || fileSize <= 0) {
        return {
            statusCode: 400,
            headers: corsHeaders,
            body: JSON.stringify({ error: 'fileSize is required and must be greater than 0' })
        };
    }

    const params = {
        Bucket,
        Key,
        ContentType: fileType || 'application/octet-stream'
    };

    try {
        console.log(`Initiating multipart upload for ${Key} with ${totalParts} parts`);
        
        // Step 1: Initiate multipart upload
        const { UploadId } = await s3.createMultipartUpload(params).promise();
        console.log(`Multipart upload initiated with UploadId: ${UploadId}`);

        // Step 2: Generate presigned URLs for all parts
        const presignedUrls = [];
        const generatePromises = [];

        for (let partNumber = 1; partNumber <= totalParts; partNumber++) {
            const uploadParams = {
                Bucket,
                Key,
                PartNumber: partNumber,
                UploadId: UploadId
            };

            // Generate presigned URLs in parallel for better performance
            generatePromises.push(
                generatePresignedUrl('uploadPart', uploadParams)
                    .then(url => ({
                        partNumber: partNumber,
                        url: url
                    }))
                    .catch(error => {
                        console.error(`Error generating presigned URL for part ${partNumber}:`, error);
                        throw error;
                    })
            );
        }

        // Wait for all presigned URLs to be generated
        const results = await Promise.all(generatePromises);
        presignedUrls.push(...results);

        // Sort by part number
        presignedUrls.sort((a, b) => a.partNumber - b.partNumber);

        console.log(`Generated ${presignedUrls.length} presigned URLs for upload ${UploadId}`);

        return {
            statusCode: 200,
            headers: corsHeaders,
            body: JSON.stringify({
                uploadId: UploadId,
                bucket: Bucket,
                key: Key,
                presignedUrls: presignedUrls
            })
        };
    } catch (error) {
        console.error('Error initiating upload:', error);
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
        console.log(`Completing multipart upload ${uploadId} with ${sortedParts.length} parts`);
        const result = await s3.completeMultipartUpload(params).promise();
        console.log(`Multipart upload completed successfully: ${result.Location}`);

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
        console.log(`Aborting multipart upload ${uploadId}`);
        await s3.abortMultipartUpload(params).promise();
        console.log(`Multipart upload ${uploadId} aborted successfully`);

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

