import React, { createContext, useContext, useReducer, useEffect } from 'react';
import { apiService } from '../services/apiService';

// Types
interface User {
  _id: string;
  name: string;
  email: string;
  role: string;
  profile: {
    playingLevel: string;
    dominantHand: string;
    preferredPosition: string;
    goals: string[];
  };
  subscription: {
    plan: string;
    videosRemaining: number;
    resetDate: string;
  };
  stats: {
    totalMatches: number;
    totalVideosUploaded: number;
    averageMatchDuration: number;
    improvementScore: number;
  };
}

interface AuthState {
  user: User | null;
  token: string | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  error: string | null;
}

type AuthAction =
  | { type: 'SET_LOADING'; payload: boolean }
  | { type: 'SET_USER'; payload: { user: User; token: string } }
  | { type: 'SET_ERROR'; payload: string }
  | { type: 'LOGOUT' }
  | { type: 'UPDATE_USER'; payload: Partial<User> };

// Initial state
const initialState: AuthState = {
  user: null,
  token: localStorage.getItem('token'),
  isLoading: true,
  isAuthenticated: false,
  error: null,
};

// Reducer
function authReducer(state: AuthState, action: AuthAction): AuthState {
  switch (action.type) {
    case 'SET_LOADING':
      return {
        ...state,
        isLoading: action.payload,
      };
    case 'SET_USER':
      return {
        ...state,
        user: action.payload.user,
        token: action.payload.token,
        isAuthenticated: true,
        isLoading: false,
        error: null,
      };
    case 'UPDATE_USER':
      return {
        ...state,
        user: state.user ? { ...state.user, ...action.payload } : null,
      };
    case 'SET_ERROR':
      return {
        ...state,
        error: action.payload,
        isLoading: false,
      };
    case 'LOGOUT':
      return {
        ...state,
        user: null,
        token: null,
        isAuthenticated: false,
        isLoading: false,
        error: null,
      };
    default:
      return state;
  }
}

// Context
interface AuthContextType extends AuthState {
  login: (email: string, password: string) => Promise<void>;
  register: (userData: {
    name: string;
    email: string;
    password: string;
    profile?: any;
  }) => Promise<void>;
  logout: () => void;
  updateProfile: (profileData: any) => Promise<void>;
  refreshUser: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

// Provider
export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [state, dispatch] = useReducer(authReducer, initialState);

  // Check if user is authenticated on app load
  useEffect(() => {
    const checkAuth = async () => {
      const token = localStorage.getItem('token');
      if (token) {
        try {
          apiService.setAuthToken(token);
          const userData = await apiService.getCurrentUser();
          dispatch({
            type: 'SET_USER',
            payload: { user: userData, token },
          });
        } catch (error) {
          localStorage.removeItem('token');
          dispatch({ type: 'LOGOUT' });
        }
      } else {
        dispatch({ type: 'SET_LOADING', payload: false });
      }
    };

    checkAuth();
  }, []);

  const login = async (email: string, password: string) => {
    try {
      dispatch({ type: 'SET_LOADING', payload: true });
      const response = await apiService.login(email, password);
      
      localStorage.setItem('token', response.token);
      apiService.setAuthToken(response.token);
      
      dispatch({
        type: 'SET_USER',
        payload: {
          user: response,
          token: response.token,
        },
      });
    } catch (error: any) {
      dispatch({
        type: 'SET_ERROR',
        payload: error.response?.data?.error || 'Login failed',
      });
      throw error;
    }
  };

  const register = async (userData: {
    name: string;
    email: string;
    password: string;
    profile?: any;
  }) => {
    try {
      dispatch({ type: 'SET_LOADING', payload: true });
      const response = await apiService.register(userData);
      
      localStorage.setItem('token', response.token);
      apiService.setAuthToken(response.token);
      
      dispatch({
        type: 'SET_USER',
        payload: {
          user: response,
          token: response.token,
        },
      });
    } catch (error: any) {
      dispatch({
        type: 'SET_ERROR',
        payload: error.response?.data?.error || 'Registration failed',
      });
      throw error;
    }
  };

  const logout = () => {
    localStorage.removeItem('token');
    apiService.setAuthToken(null);
    dispatch({ type: 'LOGOUT' });
  };

  const updateProfile = async (profileData: any) => {
    try {
      const updatedUser = await apiService.updateProfile(profileData);
      dispatch({ type: 'UPDATE_USER', payload: updatedUser });
    } catch (error: any) {
      dispatch({
        type: 'SET_ERROR',
        payload: error.response?.data?.error || 'Profile update failed',
      });
      throw error;
    }
  };

  const refreshUser = async () => {
    try {
      const userData = await apiService.getCurrentUser();
      dispatch({ type: 'UPDATE_USER', payload: userData });
    } catch (error: any) {
      console.error('Failed to refresh user data:', error);
    }
  };

  const value: AuthContextType = {
    ...state,
    login,
    register,
    logout,
    updateProfile,
    refreshUser,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

// Hook
export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}