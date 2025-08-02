import React from 'react';
import { Box, Typography, Card, CardContent, Button } from '@mui/material';
import { CloudUpload as UploadIcon } from '@mui/icons-material';

export default function VideoUpload() {
  return (
    <Box>
      <Typography variant="h4" gutterBottom sx={{ fontWeight: 600 }}>
        Upload Video
      </Typography>
      <Typography variant="body1" color="text.secondary" sx={{ mb: 4 }}>
        Upload your Padel match videos for AI-powered analysis
      </Typography>
      
      <Card>
        <CardContent sx={{ textAlign: 'center', py: 8 }}>
          <UploadIcon sx={{ fontSize: 80, color: 'primary.main', mb: 2 }} />
          <Typography variant="h5" gutterBottom>
            Video Upload Coming Soon
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
            The video upload functionality will be available here with drag-and-drop support,
            progress tracking, and match details form.
          </Typography>
          <Button variant="contained" disabled>
            Upload Video
          </Button>
        </CardContent>
      </Card>
    </Box>
  );
}