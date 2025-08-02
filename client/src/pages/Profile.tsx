import React from 'react';
import { Box, Typography, Card, CardContent, Button } from '@mui/material';
import { Person as PersonIcon } from '@mui/icons-material';

export default function Profile() {
  return (
    <Box>
      <Typography variant="h4" gutterBottom sx={{ fontWeight: 600 }}>
        Profile
      </Typography>
      <Typography variant="body1" color="text.secondary" sx={{ mb: 4 }}>
        Manage your account settings and playing preferences
      </Typography>
      
      <Card>
        <CardContent sx={{ textAlign: 'center', py: 8 }}>
          <PersonIcon sx={{ fontSize: 80, color: 'primary.main', mb: 2 }} />
          <Typography variant="h5" gutterBottom>
            Profile Settings Coming Soon
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
            Update your playing profile, manage subscription, set goals, 
            and customize your experience.
          </Typography>
          <Button variant="outlined" disabled>
            Edit Profile
          </Button>
        </CardContent>
      </Card>
    </Box>
  );
}