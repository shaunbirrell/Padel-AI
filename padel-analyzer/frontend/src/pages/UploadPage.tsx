import React, { useState, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDropzone } from 'react-dropzone';
import { Upload, Film, CheckCircle, AlertCircle, Loader } from 'lucide-react';
import { uploadVideo } from '../services/api';

const UploadPage: React.FC = () => {
  const navigate = useNavigate();
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [progress, setProgress] = useState(0);

  const onDrop = useCallback(async (acceptedFiles: File[]) => {
    if (acceptedFiles.length === 0) return;

    const file = acceptedFiles[0];
    
    // Validate file size (500MB limit)
    if (file.size > 500 * 1024 * 1024) {
      setError('File size must be less than 500MB');
      return;
    }

    setError(null);
    setUploading(true);

    try {
      // Simulate progress for demo
      const progressInterval = setInterval(() => {
        setProgress((prev) => {
          if (prev >= 90) {
            clearInterval(progressInterval);
            return prev;
          }
          return prev + 10;
        });
      }, 500);

      const response = await uploadVideo(file);
      
      clearInterval(progressInterval);
      setProgress(100);

      // Navigate to analysis page after successful upload
      setTimeout(() => {
        navigate(`/analysis/${response.video_id}`);
      }, 1000);
    } catch (err: any) {
      setError(err.response?.data?.detail || 'Failed to upload video');
      setUploading(false);
      setProgress(0);
    }
  }, [navigate]);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: {
      'video/*': ['.mp4', '.avi', '.mov', '.mkv']
    },
    maxFiles: 1,
    disabled: uploading
  });

  return (
    <div className="fade-in max-w-4xl mx-auto">
      <h1 className="text-3xl font-bold mb-8">Upload Your Padel Match Video</h1>

      {/* Upload Instructions */}
      <div className="card mb-8">
        <h2 className="text-xl font-semibold mb-4 flex items-center gap-2">
          <Film className="w-5 h-5" />
          Video Requirements
        </h2>
        <ul className="space-y-2 text-secondary">
          <li>• Supported formats: MP4, AVI, MOV, MKV</li>
          <li>• Maximum file size: 500MB</li>
          <li>• Best results with HD quality (720p or higher)</li>
          <li>• Ensure the court is clearly visible in the frame</li>
          <li>• Videos should show complete rallies for best analysis</li>
        </ul>
      </div>

      {/* Dropzone */}
      <div className="mb-8">
        <div
          {...getRootProps()}
          className={`dropzone ${isDragActive ? 'dropzone-active' : ''} ${
            uploading ? 'opacity-50 cursor-not-allowed' : ''
          }`}
        >
          <input {...getInputProps()} />
          
          {uploading ? (
            <div className="text-center">
              <Loader className="w-12 h-12 mx-auto mb-4 spinner" style={{ color: 'var(--primary-color)' }} />
              <p className="text-lg font-semibold mb-2">Uploading your video...</p>
              <div className="w-64 mx-auto bg-gray-200 rounded-full h-2 mb-2">
                <div 
                  className="h-2 rounded-full transition-all duration-300"
                  style={{ 
                    width: `${progress}%`,
                    backgroundColor: 'var(--primary-color)'
                  }}
                />
              </div>
              <p className="text-sm text-secondary">{progress}% complete</p>
            </div>
          ) : (
            <>
              <Upload className="w-12 h-12 mx-auto mb-4" style={{ color: 'var(--primary-color)' }} />
              <p className="text-lg font-semibold mb-2">
                {isDragActive ? 'Drop your video here' : 'Drag & drop your video here'}
              </p>
              <p className="text-secondary mb-4">or click to browse</p>
              <button className="btn btn-primary">
                Select Video
              </button>
            </>
          )}
        </div>
      </div>

      {/* Error Message */}
      {error && (
        <div className="card border-red-200 bg-red-50 mb-8">
          <div className="flex items-center gap-2 text-red-700">
            <AlertCircle className="w-5 h-5" />
            <p className="font-semibold">{error}</p>
          </div>
        </div>
      )}

      {/* Success Message */}
      {progress === 100 && !error && (
        <div className="card border-green-200 bg-green-50">
          <div className="flex items-center gap-2 text-green-700">
            <CheckCircle className="w-5 h-5" />
            <p className="font-semibold">Upload successful! Redirecting to analysis...</p>
          </div>
        </div>
      )}

      {/* Additional Info */}
      <div className="card bg-blue-50 border-blue-200">
        <h3 className="font-semibold mb-2 text-blue-900">Pro Tips for Best Results</h3>
        <ul className="space-y-1 text-sm text-blue-700">
          <li>• Position your camera to capture the entire court</li>
          <li>• Use a tripod or stable surface to minimize shaking</li>
          <li>• Good lighting conditions improve analysis accuracy</li>
          <li>• Include warm-up footage for technique comparison</li>
        </ul>
      </div>
    </div>
  );
};

export default UploadPage;