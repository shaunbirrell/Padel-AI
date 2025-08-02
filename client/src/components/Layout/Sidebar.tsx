import React from 'react';
import {
  Drawer,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  ListItemButton,
  Box,
  Typography,
  Divider,
  Chip,
  LinearProgress,
} from '@mui/material';
import {
  Dashboard as DashboardIcon,
  CloudUpload as UploadIcon,
  VideoLibrary as VideoLibraryIcon,
  Analytics as AnalyticsIcon,
  Person as PersonIcon,
  Settings as SettingsIcon,
} from '@mui/icons-material';
import { useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';

interface SidebarProps {
  open: boolean;
  onClose: () => void;
}

const menuItems = [
  {
    text: 'Dashboard',
    icon: <DashboardIcon />,
    path: '/dashboard',
  },
  {
    text: 'Upload Video',
    icon: <UploadIcon />,
    path: '/upload',
  },
  {
    text: 'Video Library',
    icon: <VideoLibraryIcon />,
    path: '/videos',
  },
  {
    text: 'Profile',
    icon: <PersonIcon />,
    path: '/profile',
  },
];

const drawerWidth = 240;

export default function Sidebar({ open, onClose }: SidebarProps) {
  const navigate = useNavigate();
  const location = useLocation();
  const { user } = useAuth();

  const handleNavigation = (path: string) => {
    navigate(path);
    onClose(); // Close sidebar on mobile after navigation
  };

  const getPlanColor = (plan: string) => {
    switch (plan?.toLowerCase()) {
      case 'premium':
        return 'primary';
      case 'pro':
        return 'secondary';
      default:
        return 'default';
    }
  };

  const getVideosUsedPercentage = () => {
    if (!user?.subscription) return 0;
    const totalVideos = {
      free: 3,
      pro: 20,
      premium: 100,
    }[user.subscription.plan] || 3;
    
    const used = totalVideos - user.subscription.videosRemaining;
    return (used / totalVideos) * 100;
  };

  const drawer = (
    <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      {/* Sidebar header */}
      <Box sx={{ p: 2, pt: 10 }}> {/* pt: 10 to account for navbar */}
        {user && (
          <Box>
            <Typography variant="h6" gutterBottom sx={{ fontWeight: 600 }}>
              Welcome back,
            </Typography>
            <Typography variant="body1" color="primary" sx={{ fontWeight: 500 }}>
              {user.name}
            </Typography>
            
            <Box sx={{ mt: 2 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                <Typography variant="caption" color="text.secondary">
                  Subscription
                </Typography>
                <Chip 
                  label={user.subscription?.plan?.toUpperCase() || 'FREE'} 
                  size="small" 
                  color={getPlanColor(user.subscription?.plan)}
                  variant="outlined"
                />
              </Box>
              
              <Typography variant="caption" color="text.secondary" gutterBottom>
                Videos this month: {user.subscription?.videosRemaining || 0} remaining
              </Typography>
              <LinearProgress 
                variant="determinate" 
                value={getVideosUsedPercentage()} 
                sx={{ 
                  mt: 0.5,
                  height: 6,
                  borderRadius: 3,
                  backgroundColor: 'rgba(0, 0, 0, 0.1)',
                }}
              />
            </Box>
          </Box>
        )}
      </Box>

      <Divider />

      {/* Navigation menu */}
      <List sx={{ flex: 1, pt: 1 }}>
        {menuItems.map((item) => (
          <ListItem key={item.text} disablePadding>
            <ListItemButton
              onClick={() => handleNavigation(item.path)}
              selected={location.pathname === item.path}
              sx={{
                mx: 1,
                borderRadius: 2,
                '&.Mui-selected': {
                  backgroundColor: 'primary.main',
                  color: 'white',
                  '&:hover': {
                    backgroundColor: 'primary.dark',
                  },
                  '& .MuiListItemIcon-root': {
                    color: 'white',
                  },
                },
                '&:hover': {
                  backgroundColor: 'rgba(25, 118, 210, 0.08)',
                },
              }}
            >
              <ListItemIcon
                sx={{
                  minWidth: 40,
                  color: location.pathname === item.path ? 'inherit' : 'text.secondary',
                }}
              >
                {item.icon}
              </ListItemIcon>
              <ListItemText 
                primary={item.text}
                primaryTypographyProps={{
                  fontWeight: location.pathname === item.path ? 600 : 400,
                }}
              />
            </ListItemButton>
          </ListItem>
        ))}
      </List>

      {/* Footer */}
      <Box sx={{ p: 2 }}>
        <Typography variant="caption" color="text.secondary" align="center" display="block">
          Padel Analyzer v1.0
        </Typography>
        <Typography variant="caption" color="text.secondary" align="center" display="block">
          AI-Powered Match Analysis
        </Typography>
      </Box>
    </Box>
  );

  return (
    <>
      {/* Mobile drawer */}
      <Drawer
        variant="temporary"
        open={open}
        onClose={onClose}
        ModalProps={{
          keepMounted: true, // Better open performance on mobile
        }}
        sx={{
          display: { xs: 'block', md: 'none' },
          '& .MuiDrawer-paper': {
            boxSizing: 'border-box',
            width: drawerWidth,
          },
        }}
      >
        {drawer}
      </Drawer>

      {/* Desktop drawer */}
      <Drawer
        variant="permanent"
        sx={{
          display: { xs: 'none', md: 'block' },
          '& .MuiDrawer-paper': {
            boxSizing: 'border-box',
            width: drawerWidth,
            border: 'none',
            borderRight: '1px solid rgba(0, 0, 0, 0.12)',
          },
        }}
        open
      >
        {drawer}
      </Drawer>
    </>
  );
}