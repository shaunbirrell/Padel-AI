import React from 'react';
import { Box, Typography, Card, CardContent, Button } from '@mui/material';
import { Analytics as AnalyticsIcon } from '@mui/icons-material';
import { useParams } from 'react-router-dom';

export default function VideoAnalysis() {
  const { videoId } = useParams();
  
  return (
    <Box>
      <Typography variant="h4" gutterBottom sx={{ fontWeight: 600 }}>
        Video Analysis
      </Typography>
      <Typography variant="body1" color="text.secondary" sx={{ mb: 4 }}>
        Detailed analysis results for video: {videoId}
      </Typography>
      
      <Card>
        <CardContent sx={{ textAlign: 'center', py: 8 }}>
          <AnalyticsIcon sx={{ fontSize: 80, color: 'primary.main', mb: 2 }} />
          <Typography variant="h5" gutterBottom>
            Analysis Dashboard Coming Soon
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
            View comprehensive analysis including shot breakdown, rally statistics, 
            movement analysis, and AI coaching insights.
          </Typography>
          <Button variant="outlined" disabled>
            View Analysis
          </Button>
        </CardContent>
      </Card>
    </Box>
  );
}