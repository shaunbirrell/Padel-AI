import React, { useState, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDropzone } from 'react-dropzone';
import { 
  Upload, 
  FileVideo, 
  CheckCircle, 
  AlertCircle, 
  X,
  Play,
  Clock
} from 'lucide-react';
import axios from 'axios';
import toast from 'react-hot-toast';

const VideoUpload = () => {
  const [uploadedVideos, setUploadedVideos] = useState([]);
  const [uploading, setUploading] = useState(false);
  const navigate = useNavigate();

  const onDrop = useCallback(async (acceptedFiles) => {
    setUploading(true);
    
    for (const file of acceptedFiles) {
      try {
        const formData = new FormData();
        formData.append('video', file);

        // Add file to local state immediately
        const videoId = Date.now().toString();
        const newVideo = {
          id: videoId,
          originalName: file.name,
          size: file.size,
          status: 'uploading',
          progress: 0
        };
        
        setUploadedVideos(prev => [...prev, newVideo]);

        // Upload file
        const response = await axios.post('/api/videos/upload', formData, {
          headers: {
            'Content-Type': 'multipart/form-data',
          },
          onUploadProgress: (progressEvent) => {
            const progress = Math.round((progressEvent.loaded * 100) / progressEvent.total);
            setUploadedVideos(prev => 
              prev.map(v => 
                v.id === videoId 
                  ? { ...v, progress } 
                  : v
              )
            );
          }
        });

        // Update with server response
        setUploadedVideos(prev => 
          prev.map(v => 
            v.id === videoId 
              ? { 
                  ...v, 
                  ...response.data.video,
                  status: 'uploaded',
                  progress: 100
                } 
              : v
          )
        );

        toast.success(`${file.name} uploaded successfully!`);
        
        // Start analysis automatically
        await startAnalysis(response.data.video.id);

      } catch (error) {
        console.error('Upload error:', error);
        setUploadedVideos(prev => 
          prev.map(v => 
            v.originalName === file.name 
              ? { ...v, status: 'failed' } 
              : v
          )
        );
        toast.error(`Failed to upload ${file.name}`);
      }
    }
    
    setUploading(false);
  }, []);

  const startAnalysis = async (videoId) => {
    try {
      setUploadedVideos(prev => 
        prev.map(v => 
          v.id === videoId 
            ? { ...v, analysisStatus: 'processing' } 
            : v
        )
      );

      await axios.post(`/api/analysis/analyze/${videoId}`);
      
      setUploadedVideos(prev => 
        prev.map(v => 
          v.id === videoId 
            ? { ...v, analysisStatus: 'completed' } 
            : v
        )
      );

      toast.success('Analysis completed!');
      
      // Navigate to analysis page after a short delay
      setTimeout(() => {
        navigate(`/analysis/${videoId}`);
      }, 2000);

    } catch (error) {
      console.error('Analysis error:', error);
      setUploadedVideos(prev => 
        prev.map(v => 
          v.id === videoId 
            ? { ...v, analysisStatus: 'failed' } 
            : v
        )
      );
      toast.error('Analysis failed');
    }
  };

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: {
      'video/*': ['.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm']
    },
    maxSize: 500 * 1024 * 1024, // 500MB
    multiple: true
  });

  const formatFileSize = (bytes) => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  const removeVideo = (videoId) => {
    setUploadedVideos(prev => prev.filter(v => v.id !== videoId));
  };

  const getStatusIcon = (status) => {
    switch (status) {
      case 'uploaded':
      case 'completed':
        return <CheckCircle className="h-5 w-5 text-green-500" />;
      case 'uploading':
      case 'processing':
        return <Clock className="h-5 w-5 text-yellow-500 animate-spin" />;
      case 'failed':
        return <AlertCircle className="h-5 w-5 text-red-500" />;
      default:
        return <FileVideo className="h-5 w-5 text-gray-400" />;
    }
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'uploaded':
      case 'completed':
        return 'bg-green-100 text-green-800';
      case 'uploading':
      case 'processing':
        return 'bg-yellow-100 text-yellow-800';
      case 'failed':
        return 'bg-red-100 text-red-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  return (
    <div className="max-w-4xl mx-auto space-y-8">
      {/* Header */}
      <div className="text-center">
        <h1 className="text-4xl font-bold text-gray-900 mb-4">
          Upload Padel Match Video
        </h1>
        <p className="text-xl text-gray-600">
          Upload your padel match videos to get AI-powered analysis and insights
        </p>
      </div>

      {/* Upload Zone */}
      <div className="card">
        <div
          {...getRootProps()}
          className={`upload-zone ${isDragActive ? 'upload-zone-active' : ''} ${
            uploading ? 'pointer-events-none opacity-50' : ''
          }`}
        >
          <input {...getInputProps()} />
          <Upload className="h-16 w-16 text-gray-400 mx-auto mb-4" />
          {isDragActive ? (
            <p className="text-lg font-medium text-primary-600">
              Drop your padel videos here...
            </p>
          ) : (
            <div>
              <p className="text-lg font-medium text-gray-900 mb-2">
                Drag & drop your padel match videos here
              </p>
              <p className="text-gray-600 mb-4">
                or click to browse files
              </p>
              <p className="text-sm text-gray-500">
                Supports MP4, AVI, MOV, WMV, FLV, WEBM (max 500MB each)
              </p>
            </div>
          )}
        </div>
      </div>

      {/* Upload Progress */}
      {uploadedVideos.length > 0 && (
        <div className="card">
          <h2 className="text-2xl font-bold text-gray-900 mb-6">Upload Progress</h2>
          <div className="space-y-4">
            {uploadedVideos.map((video) => (
              <div
                key={video.id}
                className="flex items-center justify-between p-4 bg-gray-50 rounded-lg"
              >
                <div className="flex items-center space-x-4">
                  {getStatusIcon(video.status)}
                  <div>
                    <h3 className="font-medium text-gray-900">{video.originalName}</h3>
                    <p className="text-sm text-gray-500">{formatFileSize(video.size)}</p>
                  </div>
                </div>

                <div className="flex items-center space-x-4">
                  {/* Progress Bar */}
                  {video.status === 'uploading' && (
                    <div className="w-32 bg-gray-200 rounded-full h-2">
                      <div
                        className="bg-primary-600 h-2 rounded-full transition-all duration-300"
                        style={{ width: `${video.progress}%` }}
                      ></div>
                    </div>
                  )}

                  {/* Status Badge */}
                  <span className={`px-3 py-1 rounded-full text-xs font-medium ${getStatusColor(video.status)}`}>
                    {video.status}
                  </span>

                  {/* Analysis Status */}
                  {video.analysisStatus && (
                    <span className={`px-3 py-1 rounded-full text-xs font-medium ${getStatusColor(video.analysisStatus)}`}>
                      {video.analysisStatus}
                    </span>
                  )}

                  {/* Remove Button */}
                  <button
                    onClick={() => removeVideo(video.id)}
                    className="text-gray-400 hover:text-red-500 transition-colors duration-200"
                  >
                    <X className="h-5 w-5" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Tips */}
      <div className="card bg-blue-50 border-blue-200">
        <h3 className="text-lg font-semibold text-blue-900 mb-4">💡 Tips for Better Analysis</h3>
        <ul className="space-y-2 text-blue-800">
          <li>• Ensure good lighting and clear video quality</li>
          <li>• Position the camera to capture the full court</li>
          <li>• Avoid shaky footage for more accurate analysis</li>
          <li>• Include both players in the frame when possible</li>
          <li>• Record from a side angle for better shot detection</li>
        </ul>
      </div>
    </div>
  );
};

export default VideoUpload;