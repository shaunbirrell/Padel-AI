import React, { useEffect, useState } from 'react';
import {
  Box,
  Grid,
  Card,
  CardContent,
  Typography,
  Button,
  CircularProgress,
  Alert,
  Stack,
  Chip,
  Avatar,
  List,
  ListItem,
  ListItemAvatar,
  ListItemText,
  ListItemButton,
} from '@mui/material';
import {
  VideoLibrary as VideoIcon,
  TrendingUp as TrendingUpIcon,
  Analytics as AnalyticsIcon,
  EmojiEvents as TrophyIcon,
  PlayArrow as PlayIcon,
  Upload as UploadIcon,
  Assessment as AssessmentIcon,
} from '@mui/icons-material';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, BarChart, Bar, PieChart, Pie, Cell } from 'recharts';
import { useNavigate } from 'react-router-dom';
import { apiService } from '../services/apiService';
import { useAuth } from '../contexts/AuthContext';
import { useNotification } from '../contexts/NotificationContext';

interface DashboardData {
  user: {
    stats: any;
    subscription: any;
    profile: any;
  };
  analytics: {
    totalVideos: number;
    completedAnalyses: number;
    averageRating: number;
    totalShots: number;
    averageAccuracy: number;
    averageRallyLength: number;
  };
  recentActivity: any[];
  improvement: {
    trend: string;
    change: number;
    firstPeriodAvg: number;
    secondPeriodAvg: number;
  };
}

const COLORS = ['#1976d2', '#ff5722', '#4caf50', '#ff9800', '#9c27b0'];

export default function Dashboard() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { showError } = useNotification();
  const [loading, setLoading] = useState(true);
  const [dashboardData, setDashboardData] = useState<DashboardData | null>(null);

  useEffect(() => {
    loadDashboardData();
  }, []);

  const loadDashboardData = async () => {
    try {
      const data = await apiService.getDashboard();
      setDashboardData(data);
    } catch (error: any) {
      showError('Failed to load dashboard data');
      console.error('Dashboard error:', error);
    } finally {
      setLoading(false);
    }
  };

  const getImprovementIcon = (trend: string) => {
    switch (trend) {
      case 'improving':
        return '📈';
      case 'declining':
        return '📉';
      case 'stable':
        return '➡️';
      default:
        return '📊';
    }
  };

  const getImprovementColor = (trend: string) => {
    switch (trend) {
      case 'improving':
        return 'success';
      case 'declining':
        return 'error';
      case 'stable':
        return 'warning';
      default:
        return 'info';
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'completed':
        return 'success';
      case 'processing':
        return 'warning';
      case 'failed':
        return 'error';
      default:
        return 'default';
    }
  };

  const formatDate = (date: string) => {
    return new Date(date).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
    });
  };

  if (loading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" minHeight="400px">
        <CircularProgress size={40} />
      </Box>
    );
  }

  if (!dashboardData) {
    return (
      <Alert severity="error">
        Failed to load dashboard data. Please refresh the page.
      </Alert>
    );
  }

  const { analytics, recentActivity, improvement } = dashboardData;

  // Sample chart data (in a real app, this would come from the API)
  const progressData = [
    { month: 'Jan', rating: 65 },
    { month: 'Feb', rating: 68 },
    { month: 'Mar', rating: 72 },
    { month: 'Apr', rating: 75 },
    { month: 'May', rating: 78 },
    { month: 'Jun', rating: 82 },
  ];

  const shotDistribution = [
    { name: 'Forehands', value: 35, color: COLORS[0] },
    { name: 'Backhands', value: 30, color: COLORS[1] },
    { name: 'Volleys', value: 20, color: COLORS[2] },
    { name: 'Smashes', value: 10, color: COLORS[3] },
    { name: 'Serves', value: 5, color: COLORS[4] },
  ];

  return (
    <Box>
      {/* Header */}
      <Box sx={{ mb: 4 }}>
        <Typography variant="h4" gutterBottom sx={{ fontWeight: 600 }}>
          Dashboard
        </Typography>
        <Typography variant="body1" color="text.secondary">
          Welcome back, {user?.name}! Here's your Padel performance overview.
        </Typography>
      </Box>

      <Grid container spacing={3}>
        {/* Quick Stats */}
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <Avatar sx={{ bgcolor: 'primary.main', mr: 2 }}>
                  <VideoIcon />
                </Avatar>
                <Box>
                  <Typography variant="h4" sx={{ fontWeight: 600 }}>
                    {analytics.totalVideos}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Total Videos
                  </Typography>
                </Box>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <Avatar sx={{ bgcolor: 'success.main', mr: 2 }}>
                  <AnalyticsIcon />
                </Avatar>
                <Box>
                  <Typography variant="h4" sx={{ fontWeight: 600 }}>
                    {analytics.completedAnalyses}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Completed Analyses
                  </Typography>
                </Box>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <Avatar sx={{ bgcolor: 'warning.main', mr: 2 }}>
                  <TrophyIcon />
                </Avatar>
                <Box>
                  <Typography variant="h4" sx={{ fontWeight: 600 }}>
                    {Math.round(analytics.averageRating || 0)}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Average Rating
                  </Typography>
                </Box>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <Avatar sx={{ bgcolor: 'secondary.main', mr: 2 }}>
                  <AssessmentIcon />
                </Avatar>
                <Box>
                  <Typography variant="h4" sx={{ fontWeight: 600 }}>
                    {Math.round(analytics.averageAccuracy || 0)}%
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Average Accuracy
                  </Typography>
                </Box>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        {/* Performance Trend */}
        <Grid item xs={12} md={8}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom sx={{ fontWeight: 600 }}>
                Performance Trend
              </Typography>
              <Box sx={{ height: 300, mt: 2 }}>
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart data={progressData}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="month" />
                    <YAxis />
                    <Tooltip />
                    <Line 
                      type="monotone" 
                      dataKey="rating" 
                      stroke={COLORS[0]} 
                      strokeWidth={3}
                      dot={{ fill: COLORS[0], strokeWidth: 2, r: 6 }}
                    />
                  </LineChart>
                </ResponsiveContainer>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        {/* Improvement Summary */}
        <Grid item xs={12} md={4}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom sx={{ fontWeight: 600 }}>
                Improvement Summary
              </Typography>
              
              <Box sx={{ textAlign: 'center', py: 2 }}>
                <Typography variant="h2" sx={{ mb: 1 }}>
                  {getImprovementIcon(improvement.trend)}
                </Typography>
                <Chip
                  label={improvement.trend.toUpperCase()}
                  color={getImprovementColor(improvement.trend) as any}
                  sx={{ mb: 2 }}
                />
                <Typography variant="h4" sx={{ fontWeight: 600, mb: 1 }}>
                  {improvement.change > 0 ? '+' : ''}{improvement.change}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  Point change from previous period
                </Typography>
              </Box>

              <Box sx={{ mt: 2 }}>
                <Typography variant="body2" color="text.secondary" gutterBottom>
                  Quick Actions
                </Typography>
                <Stack spacing={1}>
                  <Button
                    variant="outlined"
                    startIcon={<UploadIcon />}
                    fullWidth
                    onClick={() => navigate('/upload')}
                  >
                    Upload New Video
                  </Button>
                  <Button
                    variant="outlined"
                    startIcon={<VideoIcon />}
                    fullWidth
                    onClick={() => navigate('/videos')}
                  >
                    View All Videos
                  </Button>
                </Stack>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        {/* Shot Distribution */}
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom sx={{ fontWeight: 600 }}>
                Shot Distribution
              </Typography>
              <Box sx={{ height: 300, mt: 2 }}>
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={shotDistribution}
                      cx="50%"
                      cy="50%"
                      innerRadius={60}
                      outerRadius={100}
                      paddingAngle={5}
                      dataKey="value"
                    >
                      {shotDistribution.map((entry, index) => (
                        <Cell key={`cell-${index}`} fill={entry.color} />
                      ))}
                    </Pie>
                    <Tooltip />
                  </PieChart>
                </ResponsiveContainer>
              </Box>
              
              {/* Legend */}
              <Box sx={{ mt: 2 }}>
                <Grid container spacing={1}>
                  {shotDistribution.map((item, index) => (
                    <Grid item xs={6} key={index}>
                      <Box sx={{ display: 'flex', alignItems: 'center' }}>
                        <Box
                          sx={{
                            width: 12,
                            height: 12,
                            bgcolor: item.color,
                            borderRadius: 1,
                            mr: 1,
                          }}
                        />
                        <Typography variant="caption">
                          {item.name}: {item.value}%
                        </Typography>
                      </Box>
                    </Grid>
                  ))}
                </Grid>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        {/* Recent Activity */}
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom sx={{ fontWeight: 600 }}>
                Recent Activity
              </Typography>
              
              {recentActivity.length === 0 ? (
                <Box sx={{ textAlign: 'center', py: 4 }}>
                  <Typography variant="body2" color="text.secondary">
                    No recent activity. Upload your first video to get started!
                  </Typography>
                  <Button
                    variant="contained"
                    startIcon={<UploadIcon />}
                    sx={{ mt: 2 }}
                    onClick={() => navigate('/upload')}
                  >
                    Upload Video
                  </Button>
                </Box>
              ) : (
                <List>
                  {recentActivity.slice(0, 5).map((video) => (
                    <ListItem key={video._id} disablePadding>
                      <ListItemButton
                        onClick={() => {
                          if (video.analysis?.status === 'completed') {
                            navigate(`/analysis/${video._id}`);
                          } else {
                            navigate('/videos');
                          }
                        }}
                      >
                        <ListItemAvatar>
                          <Avatar sx={{ bgcolor: 'primary.main' }}>
                            <PlayIcon />
                          </Avatar>
                        </ListItemAvatar>
                        <ListItemText
                          primary={video.originalName}
                          secondary={
                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                              <Chip
                                label={video.analysis?.status || 'pending'}
                                size="small"
                                color={getStatusColor(video.analysis?.status) as any}
                                variant="outlined"
                              />
                              <Typography variant="caption" color="text.secondary">
                                {formatDate(video.createdAt)}
                              </Typography>
                            </Box>
                          }
                        />
                      </ListItemButton>
                    </ListItem>
                  ))}
                </List>
              )}
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Box>
  );
}