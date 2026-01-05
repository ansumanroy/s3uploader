/**
 * S3 Multipart Upload Handler with Pre-generated Presigned URLs
 * 
 * This module handles multipart uploads to S3 when presigned URLs are already
 * available (e.g., from an API that generates all presigned URLs upfront).
 * 
 * Usage:
 * - Call an API to get upload ID and presigned URLs for all parts
 * - Upload each part using the presigned URLs
 * - Complete the multipart upload
 * 
 * Configuration:
 * - Update apiEndpoint to point to your API that returns presigned URLs
 * - Configure chunkSize (minimum 5MB for S3)
 * - Set maxRetries for failed part uploads
 */
class S3MultipartUploaderPresigned {
    constructor(options = {}) {
        this.apiEndpoint = options.apiEndpoint || '/api/initiate-upload'; // API that returns presigned URLs
        this.completeEndpoint = options.completeEndpoint || null; // Optional: separate complete endpoint
        this.abortEndpoint = options.abortEndpoint || null; // Optional: separate abort endpoint
        this.chunkSize = options.chunkSize || 5 * 1024 * 1024; // 5MB chunks (minimum for S3)
        this.maxRetries = options.maxRetries || 3;
        this.retryDelay = options.retryDelay || 1000; // 1 second
        
        // Upload state
        this.uploadId = null;
        this.file = null;
        this.presignedUrls = [];
        this.parts = [];
        this.aborted = false;
    }

    /**
     * Format bytes to human readable string
     */
    formatBytes(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
    }

    /**
     * Get presigned URLs from API
     * 
     * Expected API response:
     * {
     *   uploadId: "abc123...",
     *   bucket: "your-bucket",
     *   key: "uploads/file.zip",
     *   presignedUrls: [
     *     { partNumber: 1, url: "https://s3.amazonaws.com/..." },
     *     { partNumber: 2, url: "https://s3.amazonaws.com/..." },
     *     ...
     *   ]
     * }
     */
    async getPresignedUrls(fileName, fileSize, fileType) {
        try {
            const totalParts = Math.ceil(fileSize / this.chunkSize);

            const response = await fetch(this.apiEndpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    fileName,
                    fileSize,
                    fileType,
                    totalParts
                })
            });

            let data;
            try {
                data = await response.json();
            } catch (error) {
                if (!response.ok) {
                    throw new Error(`Failed to get presigned URLs: ${response.statusText}`);
                }
                throw new Error('Invalid response from server');
            }

            if (!response.ok) {
                const errorMessage = data.error || data.message || response.statusText;
                throw new Error(`Failed to get presigned URLs: ${errorMessage}`);
            }

            // Validate response
            if (!data.uploadId || !data.presignedUrls || !Array.isArray(data.presignedUrls)) {
                throw new Error('Invalid response: missing uploadId or presignedUrls array');
            }

            if (data.presignedUrls.length !== totalParts) {
                throw new Error(`Invalid response: expected ${totalParts} presigned URLs, got ${data.presignedUrls.length}`);
            }

            // Sort presigned URLs by part number
            data.presignedUrls.sort((a, b) => a.partNumber - b.partNumber);

            this.uploadId = data.uploadId;
            this.presignedUrls = data.presignedUrls;
            this.bucket = data.bucket;
            this.key = data.key;

            return data;
        } catch (error) {
            console.error('Error getting presigned URLs:', error);
            throw error;
        }
    }

    /**
     * Upload a single part with retry logic
     */
    async uploadPart(partNumber, chunk, presignedUrl) {
        let retries = 0;
        
        while (retries < this.maxRetries) {
            try {
                // Upload the chunk to S3 using presigned URL
                const uploadResponse = await fetch(presignedUrl, {
                    method: 'PUT',
                    body: chunk,
                    headers: {
                        'Content-Type': 'application/octet-stream'
                    }
                });

                if (!uploadResponse.ok) {
                    throw new Error(`Upload failed: ${uploadResponse.statusText} (Status: ${uploadResponse.status})`);
                }

                // Get ETag from response headers
                const etag = uploadResponse.headers.get('ETag')?.replace(/"/g, '');
                
                if (!etag) {
                    throw new Error('No ETag received from upload');
                }

                return {
                    PartNumber: partNumber,
                    ETag: etag
                };
            } catch (error) {
                retries++;
                console.error(`Error uploading part ${partNumber} (attempt ${retries}):`, error);
                
                if (retries >= this.maxRetries) {
                    throw error;
                }
                
                // Wait before retrying (exponential backoff)
                await new Promise(resolve => setTimeout(resolve, this.retryDelay * retries));
            }
        }
    }

    /**
     * Complete multipart upload
     */
    async completeUpload(uploadId, parts, bucket, key) {
        try {
            // Try to get complete endpoint from options, or construct from initiate endpoint
            const completeEndpoint = this.completeEndpoint || this.apiEndpoint.replace('initiate-upload', 'complete-upload');
            const response = await fetch(completeEndpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    uploadId,
                    parts, // Array of {PartNumber, ETag}
                    bucket,
                    key
                })
            });

            let data;
            try {
                data = await response.json();
            } catch (error) {
                if (!response.ok) {
                    throw new Error(`Failed to complete upload: ${response.statusText}`);
                }
                throw new Error('Invalid response from server');
            }

            if (!response.ok) {
                const errorMessage = data.error || data.message || response.statusText;
                throw new Error(`Failed to complete upload: ${errorMessage}`);
            }

            return data;
        } catch (error) {
            console.error('Error completing upload:', error);
            throw error;
        }
    }

    /**
     * Abort multipart upload
     */
    async abortUpload(uploadId, bucket, key) {
        try {
            // Try to get abort endpoint from options, or construct from initiate endpoint
            const abortEndpoint = this.abortEndpoint || this.apiEndpoint.replace('initiate-upload', 'abort-upload');
            await fetch(abortEndpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    uploadId,
                    bucket,
                    key
                })
            });
        } catch (error) {
            console.error('Error aborting upload:', error);
            // Don't throw - abort is best effort
        }
    }

    /**
     * Upload file using multipart upload with presigned URLs
     */
    async upload(file, onProgress) {
        this.file = file;
        this.aborted = false;
        this.parts = [];

        try {
            // Step 1: Get presigned URLs for all parts
            if (onProgress) {
                onProgress({
                    phase: 'initiating',
                    progress: 0,
                    message: 'Getting presigned URLs...'
                });
            }

            const initData = await this.getPresignedUrls(file.name, file.size, file.type);
            const totalParts = this.presignedUrls.length;

            if (onProgress) {
                onProgress({
                    phase: 'uploading',
                    progress: 0,
                    message: `Uploading ${totalParts} parts...`,
                    totalParts,
                    uploadedParts: 0
                });
            }

            // Step 2: Upload each part with concurrency control
            const partsArray = new Array(totalParts);
            const maxConcurrent = 5; // Upload 5 parts at a time

            // Helper function to upload a single part
            const uploadSinglePart = async (partNumber, presignedUrl) => {
                if (this.aborted) {
                    throw new Error('Upload aborted');
                }

                const start = (partNumber - 1) * this.chunkSize;
                const end = Math.min(start + this.chunkSize, file.size);
                const chunk = file.slice(start, end);

                try {
                    const part = await this.uploadPart(partNumber, chunk, presignedUrl);
                    partsArray[partNumber - 1] = part;
                    
                    if (onProgress) {
                        const uploadedParts = partsArray.filter(p => p !== undefined).length;
                        const progress = (uploadedParts / totalParts) * 100;
                        
                        onProgress({
                            phase: 'uploading',
                            progress,
                            message: `Uploaded part ${uploadedParts} of ${totalParts}`,
                            totalParts,
                            uploadedParts,
                            currentPart: partNumber
                        });
                    }
                } catch (error) {
                    console.error(`Failed to upload part ${partNumber}:`, error);
                    throw error;
                }
            };

            // Upload parts with concurrency limit
            for (let i = 0; i < totalParts; i += maxConcurrent) {
                if (this.aborted) {
                    throw new Error('Upload aborted');
                }

                const batch = [];
                for (let j = 0; j < maxConcurrent && i + j < totalParts; j++) {
                    const index = i + j;
                    const partNumber = index + 1;
                    const presignedUrl = this.presignedUrls[index].url;
                    batch.push(uploadSinglePart(partNumber, presignedUrl));
                }

                await Promise.all(batch);
            }

            // Filter out undefined entries (shouldn't happen, but just in case)
            const completedParts = partsArray.filter(part => part !== undefined);

            if (onProgress) {
                onProgress({
                    phase: 'completing',
                    progress: 95,
                    message: 'Completing upload...'
                });
            }

            // Step 3: Complete multipart upload
            const result = await this.completeUpload(
                this.uploadId,
                completedParts,
                this.bucket,
                this.key
            );

            if (onProgress) {
                onProgress({
                    phase: 'completed',
                    progress: 100,
                    message: 'Upload completed successfully!',
                    result
                });
            }

            return result;
        } catch (error) {
            // Abort upload on error
            if (this.uploadId) {
                await this.abortUpload(this.uploadId, this.bucket, this.key);
            }

            if (onProgress) {
                onProgress({
                    phase: 'error',
                    progress: 0,
                    message: `Upload failed: ${error.message}`,
                    error
                });
            }

            throw error;
        }
    }

    /**
     * Abort the current upload
     */
    abort() {
        this.aborted = true;
        if (this.uploadId) {
            this.abortUpload(this.uploadId, this.bucket, this.key);
        }
    }
}

/**
 * Alternative: If you already have all presigned URLs directly
 * This version doesn't make any API calls for getting presigned URLs
 */
class S3MultipartUploaderDirectPresigned {
    constructor(options = {}) {
        this.chunkSize = options.chunkSize || 5 * 1024 * 1024; // 5MB chunks
        this.maxRetries = options.maxRetries || 3;
        this.retryDelay = options.retryDelay || 1000; // 1 second
        this.completeEndpoint = options.completeEndpoint || '/api/complete-upload';
        this.abortEndpoint = options.abortEndpoint || '/api/abort-upload';
        
        // Upload state
        this.uploadId = null;
        this.file = null;
        this.presignedUrls = [];
        this.parts = [];
        this.bucket = null;
        this.key = null;
        this.aborted = false;
    }

    /**
     * Format bytes to human readable string
     */
    formatBytes(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
    }

    /**
     * Initialize upload with presigned URLs
     * 
     * @param {Object} uploadData - Object containing:
     *   - uploadId: string
     *   - bucket: string
     *   - key: string
     *   - presignedUrls: Array of {partNumber: number, url: string}
     */
    initialize(uploadData) {
        if (!uploadData.uploadId || !uploadData.presignedUrls || !Array.isArray(uploadData.presignedUrls)) {
            throw new Error('Invalid upload data: missing uploadId or presignedUrls');
        }

        this.uploadId = uploadData.uploadId;
        this.bucket = uploadData.bucket;
        this.key = uploadData.key;
        this.presignedUrls = uploadData.presignedUrls.sort((a, b) => a.partNumber - b.partNumber);
    }

    /**
     * Upload a single part with retry logic
     */
    async uploadPart(partNumber, chunk, presignedUrl) {
        let retries = 0;
        
        while (retries < this.maxRetries) {
            try {
                const uploadResponse = await fetch(presignedUrl, {
                    method: 'PUT',
                    body: chunk,
                    headers: {
                        'Content-Type': 'application/octet-stream'
                    }
                });

                if (!uploadResponse.ok) {
                    throw new Error(`Upload failed: ${uploadResponse.statusText} (Status: ${uploadResponse.status})`);
                }

                const etag = uploadResponse.headers.get('ETag')?.replace(/"/g, '');
                
                if (!etag) {
                    throw new Error('No ETag received from upload');
                }

                return {
                    PartNumber: partNumber,
                    ETag: etag
                };
            } catch (error) {
                retries++;
                console.error(`Error uploading part ${partNumber} (attempt ${retries}):`, error);
                
                if (retries >= this.maxRetries) {
                    throw error;
                }
                
                await new Promise(resolve => setTimeout(resolve, this.retryDelay * retries));
            }
        }
    }

    /**
     * Complete multipart upload
     */
    async completeUpload(uploadId, parts) {
        try {
            const response = await fetch(this.completeEndpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    uploadId,
                    parts,
                    bucket: this.bucket,
                    key: this.key
                })
            });

            let data;
            try {
                data = await response.json();
            } catch (error) {
                if (!response.ok) {
                    throw new Error(`Failed to complete upload: ${response.statusText}`);
                }
                throw new Error('Invalid response from server');
            }

            if (!response.ok) {
                const errorMessage = data.error || data.message || response.statusText;
                throw new Error(`Failed to complete upload: ${errorMessage}`);
            }

            return data;
        } catch (error) {
            console.error('Error completing upload:', error);
            throw error;
        }
    }

    /**
     * Abort multipart upload
     */
    async abortUpload(uploadId) {
        try {
            await fetch(this.abortEndpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    uploadId,
                    bucket: this.bucket,
                    key: this.key
                })
            });
        } catch (error) {
            console.error('Error aborting upload:', error);
        }
    }

    /**
     * Upload file using presigned URLs
     */
    async upload(file, onProgress) {
        if (!this.uploadId || !this.presignedUrls.length) {
            throw new Error('Upload not initialized. Call initialize() first with presigned URLs.');
        }

        this.file = file;
        this.aborted = false;
        this.parts = [];

        try {
            const totalParts = this.presignedUrls.length;

            if (onProgress) {
                onProgress({
                    phase: 'uploading',
                    progress: 0,
                    message: `Uploading ${totalParts} parts...`,
                    totalParts,
                    uploadedParts: 0
                });
            }

            // Upload each part with concurrency control
            const partsArray = new Array(totalParts);
            const maxConcurrent = 5; // Upload 5 parts at a time
            const chunkSize = this.chunkSize;

            const uploadSinglePart = async (partNumber, presignedUrl) => {
                if (this.aborted) {
                    throw new Error('Upload aborted');
                }

                const start = (partNumber - 1) * chunkSize;
                const end = Math.min(start + chunkSize, file.size);
                const chunk = file.slice(start, end);

                try {
                    const part = await this.uploadPart(partNumber, chunk, presignedUrl);
                    partsArray[partNumber - 1] = part;
                    
                    if (onProgress) {
                        const uploadedParts = partsArray.filter(p => p !== undefined).length;
                        const progress = (uploadedParts / totalParts) * 100;
                        
                        onProgress({
                            phase: 'uploading',
                            progress,
                            message: `Uploaded part ${uploadedParts} of ${totalParts}`,
                            totalParts,
                            uploadedParts,
                            currentPart: partNumber
                        });
                    }
                } catch (error) {
                    console.error(`Failed to upload part ${partNumber}:`, error);
                    throw error;
                }
            };

            // Upload parts with concurrency limit
            for (let i = 0; i < totalParts; i += maxConcurrent) {
                if (this.aborted) {
                    throw new Error('Upload aborted');
                }

                const batch = [];
                for (let j = 0; j < maxConcurrent && i + j < totalParts; j++) {
                    const index = i + j;
                    const partNumber = this.presignedUrls[index].partNumber;
                    const presignedUrl = this.presignedUrls[index].url;
                    batch.push(uploadSinglePart(partNumber, presignedUrl));
                }

                await Promise.all(batch);
            }

            const completedParts = partsArray.filter(part => part !== undefined);

            if (onProgress) {
                onProgress({
                    phase: 'completing',
                    progress: 95,
                    message: 'Completing upload...'
                });
            }

            // Complete multipart upload
            const result = await this.completeUpload(this.uploadId, completedParts);

            if (onProgress) {
                onProgress({
                    phase: 'completed',
                    progress: 100,
                    message: 'Upload completed successfully!',
                    result
                });
            }

            return result;
        } catch (error) {
            if (this.uploadId) {
                await this.abortUpload(this.uploadId);
            }

            if (onProgress) {
                onProgress({
                    phase: 'error',
                    progress: 0,
                    message: `Upload failed: ${error.message}`,
                    error
                });
            }

            throw error;
        }
    }

    /**
     * Abort the current upload
     */
    abort() {
        this.aborted = true;
        if (this.uploadId) {
            this.abortUpload(this.uploadId);
        }
    }
}

// Export classes for use in other modules
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        S3MultipartUploaderPresigned,
        S3MultipartUploaderDirectPresigned
    };
}

