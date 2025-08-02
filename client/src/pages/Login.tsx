import React, { useState } from 'react';
import {
  Container,
  Paper,
  Box,
  Typography,
  TextField,
  Button,
  Link,
  Alert,
  CircularProgress,
  Divider,
  Stack,
} from '@mui/material';
import { Sports as SportsIcon } from '@mui/icons-material';
import { Link as RouterLink, Navigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { useNotification } from '../contexts/NotificationContext';

export default function Login() {
  const { login, isAuthenticated, isLoading, error } = useAuth();
  const { showSuccess, showError } = useNotification();
  const [formData, setFormData] = useState({
    email: '',
    password: '',
  });
  const [formLoading, setFormLoading] = useState(false);

  // Redirect if already authenticated
  if (isAuthenticated) {
    return <Navigate to="/dashboard" replace />;
  }

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFormData({
      ...formData,
      [e.target.name]: e.target.value,
    });
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormLoading(true);

    try {
      await login(formData.email, formData.password);
      showSuccess('Welcome back! Logged in successfully.');
    } catch (error: any) {
      showError(error.response?.data?.error || 'Login failed. Please try again.');
    } finally {
      setFormLoading(false);
    }
  };

  return (
    <Container component="main" maxWidth="sm">
      <Box
        sx={{
          minHeight: '100vh',
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'center',
          py: 4,
        }}
      >
        <Paper
          elevation={0}
          sx={{
            p: 4,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            border: '1px solid rgba(0, 0, 0, 0.12)',
            borderRadius: 3,
          }}
        >
          {/* Logo and Title */}
          <Box sx={{ display: 'flex', alignItems: 'center', mb: 3 }}>
            <SportsIcon sx={{ fontSize: 40, color: 'primary.main', mr: 1 }} />
            <Typography
              component="h1"
              variant="h4"
              sx={{
                fontWeight: 700,
                color: 'primary.main',
              }}
            >
              Padel Analyzer
            </Typography>
          </Box>

          <Typography variant="h5" gutterBottom sx={{ fontWeight: 600 }}>
            Welcome Back
          </Typography>
          
          <Typography variant="body2" color="text.secondary" gutterBottom sx={{ mb: 3 }}>
            Sign in to analyze your Padel matches with AI
          </Typography>

          {/* Error Alert */}
          {error && (
            <Alert severity="error" sx={{ width: '100%', mb: 2 }}>
              {error}
            </Alert>
          )}

          {/* Login Form */}
          <Box component="form" onSubmit={handleSubmit} sx={{ width: '100%' }}>
            <TextField
              margin="normal"
              required
              fullWidth
              id="email"
              label="Email Address"
              name="email"
              autoComplete="email"
              autoFocus
              value={formData.email}
              onChange={handleChange}
              disabled={formLoading}
            />
            <TextField
              margin="normal"
              required
              fullWidth
              name="password"
              label="Password"
              type="password"
              id="password"
              autoComplete="current-password"
              value={formData.password}
              onChange={handleChange}
              disabled={formLoading}
            />
            
            <Button
              type="submit"
              fullWidth
              variant="contained"
              sx={{ mt: 3, mb: 2, py: 1.5 }}
              disabled={formLoading || isLoading}
              startIcon={formLoading && <CircularProgress size={20} />}
            >
              {formLoading ? 'Signing In...' : 'Sign In'}
            </Button>

            <Divider sx={{ my: 2 }}>
              <Typography variant="body2" color="text.secondary">
                New to Padel Analyzer?
              </Typography>
            </Divider>

            <Stack direction="row" justifyContent="center" sx={{ mt: 2 }}>
              <Link
                component={RouterLink}
                to="/register"
                variant="body2"
                sx={{
                  textDecoration: 'none',
                  '&:hover': {
                    textDecoration: 'underline',
                  },
                }}
              >
                Create an account
              </Link>
            </Stack>
          </Box>

          {/* Demo Info */}
          <Box sx={{ mt: 4, p: 2, bgcolor: 'grey.50', borderRadius: 2, width: '100%' }}>
            <Typography variant="caption" color="text.secondary" gutterBottom display="block">
              Demo Credentials:
            </Typography>
            <Typography variant="body2" sx={{ fontFamily: 'monospace' }}>
              Email: demo@padelanalyzer.com<br />
              Password: demo123
            </Typography>
          </Box>
        </Paper>

        {/* Footer */}
        <Box sx={{ mt: 4, textAlign: 'center' }}>
          <Typography variant="body2" color="text.secondary">
            © 2024 Padel Analyzer. AI-powered match analysis for better gameplay.
          </Typography>
        </Box>
      </Box>
    </Container>
  );
}