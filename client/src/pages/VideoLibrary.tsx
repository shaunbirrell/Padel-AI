import React from 'react';
import { Box, Typography, Card, CardContent, Button } from '@mui/material';
import { VideoLibrary as LibraryIcon } from '@mui/icons-material';

export default function VideoLibrary() {
  return (
    <Box>
      <Typography variant="h4" gutterBottom sx={{ fontWeight: 600 }}>
        Video Library
      </Typography>
      <Typography variant="body1" color="text.secondary" sx={{ mb: 4 }}>
        Browse and manage your uploaded match videos
      </Typography>
      
      <Card>
        <CardContent sx={{ textAlign: 'center', py: 8 }}>
          <LibraryIcon sx={{ fontSize: 80, color: 'primary.main', mb: 2 }} />
          <Typography variant="h5" gutterBottom>
            Video Library Coming Soon
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
            View all your uploaded videos, filter by status, and access detailed analysis results.
          </Typography>
          <Button variant="outlined" disabled>
            Browse Videos
          </Button>
        </CardContent>
      </Card>
    </Box>
  );
}