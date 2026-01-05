/**
 * Sample Multipart Upload Implementation
 * 
 * This sample demonstrates uploading a 2GB MP4 file using 5 presigned URLs.
 * The file is split into 5 parts of approximately 400MB each.
 * 
 * Configuration:
 * - File Type: MP4 (video/mp4)
 * - File Size: ~2GB (2,000,000,000 bytes)
 * - Max Parts: 5
 * - Chunk Size: ~400MB per part
 * - Presigned URLs: Already provided (5 URLs)
 */

// Sample presigned URLs configuration
// Replace these with your actual presigned URLs
const SAMPLE_PRESIGNED_URLS = {
    uploadId: 'sample-upload-id-12345',
    bucket: 'your-bucket-name',
    key: 'uploads/sample-video.mp4',
    presignedUrls: [
        {
            partNumber: 1,
            url: 'https://s3.amazonaws.com/your-bucket/uploads/sample-video.mp4?uploadId=sample-upload-id-12345&partNumber=1&X-Amz-Algorithm=...'
        },
        {
            partNumber: 2,
            url: 'https://s3.amazonaws.com/your-bucket/uploads/sample-video.mp4?uploadId=sample-upload-id-12345&partNumber=2&X-Amz-Algorithm=...'
        },
        {
            partNumber: 3,
            url: 'https://s3.amazonaws.com/your-bucket/uploads/sample-video.mp4?uploadId=sample-upload-id-12345&partNumber=3&X-Amz-Algorithm=...'
        },
        {
            partNumber: 4,
            url: 'https://s3.amazonaws.com/your-bucket/uploads/sample-video.mp4?uploadId=sample-upload-id-12345&partNumber=4&X-Amz-Algorithm=...'
        },
        {
            partNumber: 5,
            url: 'https://s3.amazonaws.com/your-bucket/uploads/sample-video.mp4?uploadId=sample-upload-id-12345&partNumber=5&X-Amz-Algorithm=...'
        }
    ]
};

// Sample Uploader UI
class SampleUploaderUI {
    constructor() {
        // Initialize uploader with direct presigned URLs
        // Chunk size will be calculated dynamically based on file size and number of parts
        this.uploader = new S3MultipartUploaderDirectPresigned({
            chunkSize: 400 * 1024 * 1024, // Default: 400MB per part (will be updated based on file size)
            maxRetries: 3,
            completeEndpoint: '/api/complete-upload', // Update this to your complete endpoint
            abortEndpoint: '/api/abort-upload' // Update this to your abort endpoint
        });

        this.presignedConfig = null;
        this.selectedFile = null;
        this.initializeElements();
        this.attachEventListeners();
        this.loadSampleConfig();
    }

    initializeElements() {
        this.uploadArea = document.getElementById('uploadArea');
        this.fileInput = document.getElementById('fileInput');
        this.fileInfo = document.getElementById('fileInfo');
        this.fileName = document.getElementById('fileName');
        this.fileSize = document.getElementById('fileSize');
        this.fileType = document.getElementById('fileType');
        this.presignedUrlsInfo = document.getElementById('presignedUrlsInfo');
        this.uploadBtn = document.getElementById('uploadBtn');
        this.progressContainer = document.getElementById('progressContainer');
        this.progressFill = document.getElementById('progressFill');
        this.progressText = document.getElementById('progressText');
        this.partProgress = document.getElementById('partProgress');
        this.status = document.getElementById('status');
        
        // Presigned URLs configuration elements
        this.uploadIdInput = document.getElementById('uploadId');
        this.bucketInput = document.getElementById('bucket');
        this.keyInput = document.getElementById('key');
        this.presignedUrlsInput = document.getElementById('presignedUrls');
        this.loadPresignedUrlsBtn = document.getElementById('loadPresignedUrls');
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

        // Load presigned URLs button
        this.loadPresignedUrlsBtn.addEventListener('click', () => {
            this.loadPresignedUrlsFromInput();
        });
    }

    loadSampleConfig() {
        // Load sample configuration into inputs
        this.uploadIdInput.value = SAMPLE_PRESIGNED_URLS.uploadId;
        this.bucketInput.value = SAMPLE_PRESIGNED_URLS.bucket;
        this.keyInput.value = SAMPLE_PRESIGNED_URLS.key;
        this.presignedUrlsInput.value = JSON.stringify(SAMPLE_PRESIGNED_URLS.presignedUrls, null, 2);
        
        // Initialize with sample config
        this.presignedConfig = { ...SAMPLE_PRESIGNED_URLS };
        this.updatePresignedUrlsInfo();
    }

    loadPresignedUrlsFromInput() {
        try {
            const uploadId = this.uploadIdInput.value.trim();
            const bucket = this.bucketInput.value.trim();
            const key = this.keyInput.value.trim();
            const presignedUrlsJson = this.presignedUrlsInput.value.trim();

            if (!uploadId || !bucket || !key || !presignedUrlsJson) {
                this.showStatus('Please fill in all fields', 'error');
                return;
            }

            const presignedUrls = JSON.parse(presignedUrlsJson);

            if (!Array.isArray(presignedUrls) || presignedUrls.length === 0) {
                this.showStatus('Presigned URLs must be a non-empty array', 'error');
                return;
            }

            // Validate presigned URLs
            for (let i = 0; i < presignedUrls.length; i++) {
                const url = presignedUrls[i];
                if (!url.partNumber || !url.url) {
                    this.showStatus(`Invalid presigned URL at index ${i}: missing partNumber or url`, 'error');
                    return;
                }
            }

            this.presignedConfig = {
                uploadId,
                bucket,
                key,
                presignedUrls: presignedUrls.sort((a, b) => a.partNumber - b.partNumber)
            };

            this.updatePresignedUrlsInfo();
            this.showStatus(`Loaded ${presignedUrls.length} presigned URLs successfully`, 'success');
            
            // Enable upload button if file is selected
            if (this.selectedFile) {
                this.uploadBtn.disabled = false;
            }
        } catch (error) {
            console.error('Error loading presigned URLs:', error);
            this.showStatus(`Error loading presigned URLs: ${error.message}`, 'error');
        }
    }

    updatePresignedUrlsInfo() {
        if (this.presignedConfig && this.presignedConfig.presignedUrls) {
            const count = this.presignedConfig.presignedUrls.length;
            this.presignedUrlsInfo.textContent = `✅ ${count} presigned URLs loaded (Parts: ${this.presignedConfig.presignedUrls.map(u => u.partNumber).join(', ')})`;
            this.presignedUrlsInfo.style.background = '#d4edda';
            this.presignedUrlsInfo.style.borderColor = '#c3e6cb';
            this.presignedUrlsInfo.style.color = '#155724';
        } else {
            this.presignedUrlsInfo.textContent = '⚠️ Presigned URLs not loaded';
            this.presignedUrlsInfo.style.background = '#fff3cd';
            this.presignedUrlsInfo.style.borderColor = '#ffc107';
            this.presignedUrlsInfo.style.color = '#856404';
        }
    }

    handleFileSelect(file) {
        // Validate file type
        if (file.type !== 'video/mp4' && !file.name.toLowerCase().endsWith('.mp4')) {
            this.showStatus('Please select an MP4 file', 'error');
            return;
        }

        // Validate file size (approximately 2GB)
        const expectedSize = 2 * 1024 * 1024 * 1024; // 2GB
        const tolerance = 100 * 1024 * 1024; // 100MB tolerance
        if (Math.abs(file.size - expectedSize) > tolerance) {
            console.warn(`File size (${file.size}) differs from expected size (${expectedSize})`);
        }

        this.selectedFile = file;
        this.fileName.textContent = file.name;
        this.fileSize.textContent = this.uploader.formatBytes(file.size);
        this.fileType.textContent = `Type: ${file.type || 'video/mp4'}`;
        this.fileInfo.classList.add('show');
        this.hideStatus();

        // Enable upload button if presigned URLs are loaded
        if (this.presignedConfig && this.presignedConfig.presignedUrls) {
            this.uploadBtn.disabled = false;
        } else {
            this.showStatus('Please load presigned URLs first', 'info');
        }
    }

    showStatus(message, type = 'info') {
        this.status.textContent = message;
        this.status.className = `status ${type} show`;
        
        // Auto-hide success messages after 5 seconds
        if (type === 'success') {
            setTimeout(() => {
                this.hideStatus();
            }, 5000);
        }
    }

    hideStatus() {
        this.status.classList.remove('show');
    }

    formatBytes(bytes) {
        return this.uploader.formatBytes(bytes);
    }

    updateProgress(progress) {
        if (progress.phase === 'uploading') {
            this.progressContainer.classList.add('show');
            const percentage = Math.round(progress.progress);
            this.progressFill.style.width = `${percentage}%`;
            this.progressFill.textContent = `${percentage}%`;
            this.progressText.textContent = progress.message || `Uploading... ${percentage}%`;
            
            if (progress.totalParts && progress.uploadedParts !== undefined) {
                this.partProgress.textContent = `Part ${progress.uploadedParts} of ${progress.totalParts} uploaded (${progress.currentPart ? `Currently uploading part ${progress.currentPart}` : ''})`;
            }
        } else if (progress.phase === 'completing') {
            this.progressFill.style.width = '95%';
            this.progressFill.textContent = '95%';
            this.progressText.textContent = 'Completing upload...';
            this.partProgress.textContent = 'All parts uploaded, completing multipart upload...';
        } else if (progress.phase === 'completed') {
            this.progressFill.style.width = '100%';
            this.progressFill.textContent = '100%';
            this.progressText.textContent = 'Upload completed!';
            this.partProgress.textContent = '';
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

        if (!this.presignedConfig || !this.presignedConfig.presignedUrls) {
            this.showStatus('Please load presigned URLs first', 'error');
            return;
        }

        // Calculate chunk size based on file size and number of parts
        const totalParts = this.presignedConfig.presignedUrls.length;
        const fileSize = this.selectedFile.size;
        const chunkSize = Math.ceil(fileSize / totalParts);

        console.log(`File size: ${this.formatBytes(fileSize)}`);
        console.log(`Total parts: ${totalParts}`);
        console.log(`Chunk size: ${this.formatBytes(chunkSize)} per part`);

        // Update uploader chunk size to match file size and number of parts
        this.uploader.chunkSize = chunkSize;

        // Validate that we have the correct number of presigned URLs
        if (totalParts !== 5) {
            console.warn(`Expected 5 parts, but found ${totalParts} presigned URLs`);
        }

        // Validate file size is approximately 2GB
        const expectedSize = 2 * 1024 * 1024 * 1024; // 2GB
        const tolerance = 100 * 1024 * 1024; // 100MB tolerance
        if (Math.abs(fileSize - expectedSize) > tolerance) {
            console.warn(`File size (${this.formatBytes(fileSize)}) differs from expected size (${this.formatBytes(expectedSize)})`);
        }

        // Initialize uploader with presigned URLs
        try {
            this.uploader.initialize(this.presignedConfig);
        } catch (error) {
            this.showStatus(`Error initializing uploader: ${error.message}`, 'error');
            return;
        }

        this.uploadBtn.disabled = true;
        this.uploadBtn.textContent = 'Uploading...';
        this.hideStatus();
        this.progressContainer.classList.add('show');

        try {
            const result = await this.uploader.upload(this.selectedFile, (progress) => {
                this.updateProgress(progress);
            });

            console.log('Upload result:', result);
            this.showStatus(`Upload completed successfully! Location: ${result.location || 'N/A'}`, 'success');
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
    new SampleUploaderUI();
});

