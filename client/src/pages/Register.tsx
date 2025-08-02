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
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  SelectChangeEvent,
} from '@mui/material';
import { Sports as SportsIcon } from '@mui/icons-material';
import { Link as RouterLink, Navigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { useNotification } from '../contexts/NotificationContext';

interface FormData {
  name: string;
  email: string;
  password: string;
  confirmPassword: string;
  playingLevel: string;
  dominantHand: string;
  preferredPosition: string;
}

export default function Register() {
  const { register, isAuthenticated, isLoading, error } = useAuth();
  const { showSuccess, showError } = useNotification();
  const [formData, setFormData] = useState<FormData>({
    name: '',
    email: '',
    password: '',
    confirmPassword: '',
    playingLevel: 'beginner',
    dominantHand: 'right',
    preferredPosition: 'both',
  });
  const [formLoading, setFormLoading] = useState(false);
  const [formErrors, setFormErrors] = useState<Record<string, string>>({});

  // Redirect if already authenticated
  if (isAuthenticated) {
    return <Navigate to="/dashboard" replace />;
  }

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value,
    }));
    
    // Clear specific field error when user starts typing
    if (formErrors[name]) {
      setFormErrors(prev => ({
        ...prev,
        [name]: '',
      }));
    }
  };

  const handleSelectChange = (e: SelectChangeEvent) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value,
    }));
  };

  const validateForm = (): boolean => {
    const errors: Record<string, string> = {};

    if (!formData.name.trim()) {
      errors.name = 'Name is required';
    }

    if (!formData.email.trim()) {
      errors.email = 'Email is required';
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(formData.email)) {
      errors.email = 'Please enter a valid email address';
    }

    if (!formData.password) {
      errors.password = 'Password is required';
    } else if (formData.password.length < 6) {
      errors.password = 'Password must be at least 6 characters long';
    }

    if (formData.password !== formData.confirmPassword) {
      errors.confirmPassword = 'Passwords do not match';
    }

    setFormErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!validateForm()) {
      return;
    }

    setFormLoading(true);

    try {
      const { confirmPassword, ...registrationData } = formData;
      await register({
        ...registrationData,
        profile: {
          playingLevel: formData.playingLevel,
          dominantHand: formData.dominantHand,
          preferredPosition: formData.preferredPosition,
        },
      });
      showSuccess('Account created successfully! Welcome to Padel Analyzer.');
    } catch (error: any) {
      showError(error.response?.data?.error || 'Registration failed. Please try again.');
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
            Create Account
          </Typography>
          
          <Typography variant="body2" color="text.secondary" gutterBottom sx={{ mb: 3, textAlign: 'center' }}>
            Join thousands of players improving their game with AI analysis
          </Typography>

          {/* Error Alert */}
          {error && (
            <Alert severity="error" sx={{ width: '100%', mb: 2 }}>
              {error}
            </Alert>
          )}

          {/* Registration Form */}
          <Box component="form" onSubmit={handleSubmit} sx={{ width: '100%' }}>
            <TextField
              margin="normal"
              required
              fullWidth
              id="name"
              label="Full Name"
              name="name"
              autoComplete="name"
              autoFocus
              value={formData.name}
              onChange={handleChange}
              disabled={formLoading}
              error={!!formErrors.name}
              helperText={formErrors.name}
            />
            
            <TextField
              margin="normal"
              required
              fullWidth
              id="email"
              label="Email Address"
              name="email"
              autoComplete="email"
              value={formData.email}
              onChange={handleChange}
              disabled={formLoading}
              error={!!formErrors.email}
              helperText={formErrors.email}
            />
            
            <TextField
              margin="normal"
              required
              fullWidth
              name="password"
              label="Password"
              type="password"
              id="password"
              autoComplete="new-password"
              value={formData.password}
              onChange={handleChange}
              disabled={formLoading}
              error={!!formErrors.password}
              helperText={formErrors.password}
            />
            
            <TextField
              margin="normal"
              required
              fullWidth
              name="confirmPassword"
              label="Confirm Password"
              type="password"
              id="confirmPassword"
              value={formData.confirmPassword}
              onChange={handleChange}
              disabled={formLoading}
              error={!!formErrors.confirmPassword}
              helperText={formErrors.confirmPassword}
            />

            <Divider sx={{ my: 3 }}>
              <Typography variant="body2" color="text.secondary">
                Playing Profile
              </Typography>
            </Divider>

            <Stack spacing={2}>
              <FormControl fullWidth>
                <InputLabel>Playing Level</InputLabel>
                <Select
                  name="playingLevel"
                  value={formData.playingLevel}
                  label="Playing Level"
                  onChange={handleSelectChange}
                  disabled={formLoading}
                >
                  <MenuItem value="beginner">Beginner</MenuItem>
                  <MenuItem value="intermediate">Intermediate</MenuItem>
                  <MenuItem value="advanced">Advanced</MenuItem>
                  <MenuItem value="professional">Professional</MenuItem>
                </Select>
              </FormControl>

              <FormControl fullWidth>
                <InputLabel>Dominant Hand</InputLabel>
                <Select
                  name="dominantHand"
                  value={formData.dominantHand}
                  label="Dominant Hand"
                  onChange={handleSelectChange}
                  disabled={formLoading}
                >
                  <MenuItem value="right">Right</MenuItem>
                  <MenuItem value="left">Left</MenuItem>
                </Select>
              </FormControl>

              <FormControl fullWidth>
                <InputLabel>Preferred Position</InputLabel>
                <Select
                  name="preferredPosition"
                  value={formData.preferredPosition}
                  label="Preferred Position"
                  onChange={handleSelectChange}
                  disabled={formLoading}
                >
                  <MenuItem value="forehand">Forehand Side</MenuItem>
                  <MenuItem value="backhand">Backhand Side</MenuItem>
                  <MenuItem value="both">Both Sides</MenuItem>
                </Select>
              </FormControl>
            </Stack>
            
            <Button
              type="submit"
              fullWidth
              variant="contained"
              sx={{ mt: 3, mb: 2, py: 1.5 }}
              disabled={formLoading || isLoading}
              startIcon={formLoading && <CircularProgress size={20} />}
            >
              {formLoading ? 'Creating Account...' : 'Create Account'}
            </Button>

            <Divider sx={{ my: 2 }}>
              <Typography variant="body2" color="text.secondary">
                Already have an account?
              </Typography>
            </Divider>

            <Stack direction="row" justifyContent="center" sx={{ mt: 2 }}>
              <Link
                component={RouterLink}
                to="/login"
                variant="body2"
                sx={{
                  textDecoration: 'none',
                  '&:hover': {
                    textDecoration: 'underline',
                  },
                }}
              >
                Sign in instead
              </Link>
            </Stack>
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