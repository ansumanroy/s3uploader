/**
 * S3 Multipart Upload Handler
 * 
 * This module handles multipart uploads to S3 using presigned URLs.
 * 
 * Configuration:
 * - Update apiEndpoint in UploadUI constructor to point to your Lambda function
 * - Configure chunkSize (minimum 5MB for S3)
 * - Set maxRetries for failed part uploads
 */
class S3MultipartUploader {
    constructor(options = {}) {
        this.apiEndpoint = options.apiEndpoint || '/api/presigned-url'; // Lambda function endpoint
        this.chunkSize = options.chunkSize || 5 * 1024 * 1024; // 5MB chunks (minimum for S3)
        this.maxRetries = options.maxRetries || 3;
        this.retryDelay = options.retryDelay || 1000; // 1 second
        this.bucket = options.bucket || null;
        this.key = options.key || null;
        
        // Upload state
        this.uploadId = null;
        this.file = null;
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
     * Get presigned URL from Lambda function
     */
    async getPresignedUrl(operation, params = {}) {
        try {
            const response = await fetch(this.apiEndpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    operation, // 'initiate', 'upload', 'complete', 'abort'
                    ...params
                })
            });

            let data;
            try {
                data = await response.json();
            } catch (error) {
                // If response is not JSON, use status text
                if (!response.ok) {
                    throw new Error(`Failed to get presigned URL: ${response.statusText}`);
                }
                throw new Error('Invalid response from server');
            }

            if (!response.ok) {
                const errorMessage = data.error || data.message || response.statusText;
                throw new Error(`Failed to get presigned URL: ${errorMessage}`);
            }

            return data;
        } catch (error) {
            console.error('Error getting presigned URL:', error);
            throw error;
        }
    }

    /**
     * Initiate multipart upload
     */
    async initiateUpload(fileName, fileType) {
        try {
            const response = await this.getPresignedUrl('initiate', {
                fileName,
                fileType,
                bucket: this.bucket,
                key: this.key || fileName
            });

            if (response.uploadId && response.bucket && response.key) {
                this.uploadId = response.uploadId;
                this.bucket = response.bucket;
                this.key = response.key;
                return response;
            } else {
                throw new Error('Invalid response from initiate upload');
            }
        } catch (error) {
            console.error('Error initiating upload:', error);
            throw error;
        }
    }

    /**
     * Upload a single part with retry logic
     */
    async uploadPart(partNumber, chunk, uploadId) {
        let retries = 0;
        
        while (retries < this.maxRetries) {
            try {
                // Get presigned URL for this part
                const presignedData = await this.getPresignedUrl('upload', {
                    uploadId,
                    partNumber,
                    bucket: this.bucket,
                    key: this.key
                });

                if (!presignedData.url) {
                    throw new Error('No presigned URL received for part upload');
                }

                // Upload the chunk to S3
                const uploadResponse = await fetch(presignedData.url, {
                    method: 'PUT',
                    body: chunk,
                    headers: {
                        'Content-Type': 'application/octet-stream'
                    }
                });

                if (!uploadResponse.ok) {
                    throw new Error(`Upload failed: ${uploadResponse.statusText}`);
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
                
                // Wait before retrying
                await new Promise(resolve => setTimeout(resolve, this.retryDelay * retries));
            }
        }
    }

    /**
     * Complete multipart upload
     */
    async completeUpload(uploadId, parts) {
        try {
            const response = await this.getPresignedUrl('complete', {
                uploadId,
                parts, // Array of {PartNumber, ETag}
                bucket: this.bucket,
                key: this.key
            });

            return response;
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
            await this.getPresignedUrl('abort', {
                uploadId,
                bucket: this.bucket,
                key: this.key
            });
        } catch (error) {
            console.error('Error aborting upload:', error);
            // Don't throw - abort is best effort
        }
    }

    /**
     * Upload file using multipart upload
     */
    async upload(file, onProgress) {
        this.file = file;
        this.aborted = false;
        this.parts = [];

        try {
            // Step 1: Initiate multipart upload
            if (onProgress) {
                onProgress({
                    phase: 'initiating',
                    progress: 0,
                    message: 'Initiating multipart upload...'
                });
            }

            await this.initiateUpload(file.name, file.type);

            // Step 2: Calculate number of parts
            const totalParts = Math.ceil(file.size / this.chunkSize);
            
            if (onProgress) {
                onProgress({
                    phase: 'uploading',
                    progress: 0,
                    message: `Uploading ${totalParts} parts...`,
                    totalParts,
                    uploadedParts: 0
                });
            }

            // Step 3: Upload each part with concurrency control
            const partsArray = new Array(totalParts);
            const maxConcurrent = 5; // Upload 5 parts at a time

            // Helper function to upload a single part
            const uploadSinglePart = async (partNumber) => {
                if (this.aborted) {
                    throw new Error('Upload aborted');
                }

                const start = (partNumber - 1) * this.chunkSize;
                const end = Math.min(start + this.chunkSize, file.size);
                const chunk = file.slice(start, end);

                try {
                    const part = await this.uploadPart(partNumber, chunk, this.uploadId);
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
                    const partNumber = i + j + 1;
                    batch.push(uploadSinglePart(partNumber));
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

            // Step 4: Complete multipart upload
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
            // Abort upload on error
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

// UI Handler
class UploadUI {
    constructor() {
        this.uploader = new S3MultipartUploader({
            apiEndpoint: '/api/presigned-url', // Update this to your Lambda endpoint
            chunkSize: 5 * 1024 * 1024, // 5MB chunks
            maxRetries: 3
        });

        this.initializeElements();
        this.attachEventListeners();
    }

    initializeElements() {
        this.uploadArea = document.getElementById('uploadArea');
        this.fileInput = document.getElementById('fileInput');
        this.fileInfo = document.getElementById('fileInfo');
        this.fileName = document.getElementById('fileName');
        this.fileSize = document.getElementById('fileSize');
        this.uploadBtn = document.getElementById('uploadBtn');
        this.progressContainer = document.getElementById('progressContainer');
        this.progressFill = document.getElementById('progressFill');
        this.progressText = document.getElementById('progressText');
        this.partProgress = document.getElementById('partProgress');
        this.status = document.getElementById('status');
    }

    attachEventListeners() {
        // Click to select file
        this.uploadArea.addEventListener('click', () => {
            this.fileInput.click();
        });

        // File input change
        this.fileInput.addEventListener('change', (e) => {
            if (e.target.files.length > 0) {
                this.handleFileSelect(e.target.files[0]);
            }
        });

        // Drag and drop
        this.uploadArea.addEventListener('dragover', (e) => {
            e.preventDefault();
            this.uploadArea.classList.add('dragover');
        });

        this.uploadArea.addEventListener('dragleave', () => {
            this.uploadArea.classList.remove('dragover');
        });

        this.uploadArea.addEventListener('drop', (e) => {
            e.preventDefault();
            this.uploadArea.classList.remove('dragover');
            
            if (e.dataTransfer.files.length > 0) {
                this.handleFileSelect(e.dataTransfer.files[0]);
            }
        });

        // Upload button
        this.uploadBtn.addEventListener('click', () => {
            this.startUpload();
        });
    }

    handleFileSelect(file) {
        this.selectedFile = file;
        this.fileName.textContent = file.name;
        this.fileSize.textContent = this.uploader.formatBytes(file.size);
        this.fileInfo.classList.add('show');
        this.uploadBtn.disabled = false;
        this.hideStatus();
    }

    showStatus(message, type = 'info') {
        this.status.textContent = message;
        this.status.className = `status ${type} show`;
    }

    hideStatus() {
        this.status.classList.remove('show');
    }

    updateProgress(progress) {
        if (progress.phase === 'initiating') {
            this.progressContainer.classList.add('show');
            this.progressFill.style.width = '5%';
            this.progressFill.textContent = '0%';
            this.progressText.textContent = 'Initiating upload...';
        } else if (progress.phase === 'uploading') {
            const percentage = Math.round(progress.progress);
            this.progressFill.style.width = `${percentage}%`;
            this.progressFill.textContent = `${percentage}%`;
            this.progressText.textContent = progress.message || `Uploading... ${percentage}%`;
            
            if (progress.totalParts && progress.uploadedParts !== undefined) {
                this.partProgress.textContent = `Part ${progress.uploadedParts} of ${progress.totalParts} uploaded`;
            }
        } else if (progress.phase === 'completing') {
            this.progressFill.style.width = '95%';
            this.progressFill.textContent = '95%';
            this.progressText.textContent = 'Completing upload...';
        } else if (progress.phase === 'completed') {
            this.progressFill.style.width = '100%';
            this.progressFill.textContent = '100%';
            this.progressText.textContent = 'Upload completed!';
            this.showStatus('File uploaded successfully!', 'success');
            this.uploadBtn.disabled = false;
            this.uploadBtn.textContent = 'Upload Another File';
        } else if (progress.phase === 'error') {
            this.showStatus(progress.message || 'Upload failed', 'error');
            this.uploadBtn.disabled = false;
            this.uploadBtn.textContent = 'Retry Upload';
        }
    }

    async startUpload() {
        if (!this.selectedFile) {
            this.showStatus('Please select a file first', 'error');
            return;
        }

        this.uploadBtn.disabled = true;
        this.uploadBtn.textContent = 'Uploading...';
        this.hideStatus();
        this.progressContainer.classList.add('show');

        try {
            await this.uploader.upload(this.selectedFile, (progress) => {
                this.updateProgress(progress);
            });
        } catch (error) {
            console.error('Upload error:', error);
            this.showStatus(`Upload failed: ${error.message}`, 'error');
            this.uploadBtn.disabled = false;
            this.uploadBtn.textContent = 'Retry Upload';
        }
    }
}

// Initialize UI when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    new UploadUI();
});

