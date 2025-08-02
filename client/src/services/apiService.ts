import axios, { AxiosInstance, AxiosRequestConfig } from 'axios';

class ApiService {
  private api: AxiosInstance;

  constructor() {
    this.api = axios.create({
      baseURL: process.env.REACT_APP_API_URL || 'http://localhost:5000/api',
      headers: {
        'Content-Type': 'application/json',
      },
    });

    // Add request interceptor to include auth token
    this.api.interceptors.request.use((config) => {
      const token = localStorage.getItem('token');
      if (token) {
        config.headers.Authorization = `Bearer ${token}`;
      }
      return config;
    });

    // Add response interceptor to handle errors
    this.api.interceptors.response.use(
      (response) => response,
      (error) => {
        if (error.response?.status === 401) {
          localStorage.removeItem('token');
          window.location.href = '/login';
        }
        return Promise.reject(error);
      }
    );
  }

  setAuthToken(token: string | null) {
    if (token) {
      this.api.defaults.headers.common['Authorization'] = `Bearer ${token}`;
    } else {
      delete this.api.defaults.headers.common['Authorization'];
    }
  }

  // Authentication endpoints
  async login(email: string, password: string) {
    const response = await this.api.post('/auth/login', { email, password });
    return response.data;
  }

  async register(userData: any) {
    const response = await this.api.post('/auth/register', userData);
    return response.data;
  }

  async getCurrentUser() {
    const response = await this.api.get('/auth/me');
    return response.data;
  }

  async updateProfile(profileData: any) {
    const response = await this.api.put('/auth/profile', profileData);
    return response.data;
  }

  async changePassword(passwordData: any) {
    const response = await this.api.put('/auth/password', passwordData);
    return response.data;
  }

  // Video endpoints
  async uploadVideo(formData: FormData, onProgress?: (progress: number) => void) {
    const config: AxiosRequestConfig = {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
    };

    if (onProgress) {
      config.onUploadProgress = (progressEvent) => {
        const progress = progressEvent.total 
          ? Math.round((progressEvent.loaded * 100) / progressEvent.total)
          : 0;
        onProgress(progress);
      };
    }

    const response = await this.api.post('/videos/upload', formData, config);
    return response.data;
  }

  async getVideos(params?: { page?: number; limit?: number; status?: string }) {
    const response = await this.api.get('/videos', { params });
    return response.data;
  }

  async getVideo(videoId: string) {
    const response = await this.api.get(`/videos/${videoId}`);
    return response.data;
  }

  async updateVideo(videoId: string, updateData: any) {
    const response = await this.api.put(`/videos/${videoId}`, updateData);
    return response.data;
  }

  async deleteVideo(videoId: string) {
    const response = await this.api.delete(`/videos/${videoId}`);
    return response.data;
  }

  async getVideoProgress(videoId: string) {
    const response = await this.api.get(`/videos/${videoId}/progress`);
    return response.data;
  }

  async getVideoStats() {
    const response = await this.api.get('/videos/stats/overview');
    return response.data;
  }

  // Analysis endpoints
  async getAnalysis(videoId: string) {
    const response = await this.api.get(`/analysis/${videoId}`);
    return response.data;
  }

  async getShotAnalysis(videoId: string) {
    const response = await this.api.get(`/analysis/${videoId}/shots`);
    return response.data;
  }

  async getRallyAnalysis(videoId: string) {
    const response = await this.api.get(`/analysis/${videoId}/rallies`);
    return response.data;
  }

  async getMovementAnalysis(videoId: string) {
    const response = await this.api.get(`/analysis/${videoId}/movement`);
    return response.data;
  }

  async getPerformanceAnalysis(videoId: string) {
    const response = await this.api.get(`/analysis/${videoId}/performance`);
    return response.data;
  }

  async getCoachingInsights(videoId: string) {
    const response = await this.api.get(`/analysis/${videoId}/coaching`);
    return response.data;
  }

  async compareVideos(videoIds: string[]) {
    const response = await this.api.post('/analysis/compare', { videoIds });
    return response.data;
  }

  // User endpoints
  async getDashboard() {
    const response = await this.api.get('/users/dashboard');
    return response.data;
  }

  async getProgress(timeframe?: number) {
    const params = timeframe ? { timeframe } : {};
    const response = await this.api.get('/users/progress', { params });
    return response.data;
  }

  async getAchievements() {
    const response = await this.api.get('/users/achievements');
    return response.data;
  }

  async updateGoals(goals: string[]) {
    const response = await this.api.put('/users/goals', { goals });
    return response.data;
  }

  async updateSubscription(plan: string) {
    const response = await this.api.put('/users/subscription', { plan });
    return response.data;
  }

  async deleteAccount() {
    const response = await this.api.delete('/users/account');
    return response.data;
  }

  // Health check
  async healthCheck() {
    const response = await this.api.get('/health');
    return response.data;
  }
}

export const apiService = new ApiService();