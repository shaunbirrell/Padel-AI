import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import ReactPlayer from 'react-player';
import {
  BarChart, Bar, LineChart, Line, PieChart, Pie, Cell, RadarChart, Radar,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, PolarGrid, PolarAngleAxis, PolarRadiusAxis
} from 'recharts';
import { 
  Play, Pause, SkipForward, SkipBack, Target, TrendingUp, 
  Users, Award, AlertCircle, Clock, Activity, Zap
} from 'lucide-react';
import { getAnalysis, VideoAnalysis } from '../services/api';

const AnalysisPage: React.FC = () => {
  const { videoId } = useParams<{ videoId: string }>();
  const navigate = useNavigate();
  const [analysis, setAnalysis] = useState<VideoAnalysis | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [selectedRally, setSelectedRally] = useState<number | null>(null);
  const [activeTab, setActiveTab] = useState<'overview' | 'rallies' | 'technical' | 'recommendations'>('overview');

  useEffect(() => {
    if (videoId) {
      fetchAnalysis();
    }
  }, [videoId]);

  const fetchAnalysis = async () => {
    try {
      setLoading(true);
      const data = await getAnalysis(videoId!);
      
      if (data.status === 'completed' && data.analysis) {
        setAnalysis(data);
      } else if (data.status === 'analyzing') {
        // Poll for results
        setTimeout(fetchAnalysis, 5000);
      } else {
        setError('Analysis not available');
      }
    } catch (err) {
      setError('Failed to load analysis');
    } finally {
      setLoading(false);
    }
  };

  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  if (loading) {
    return (
      <div className="loading-container">
        <div className="loading-spinner" />
        <p className="text-secondary">Loading analysis...</p>
      </div>
    );
  }

  if (error || !analysis?.analysis) {
    return (
      <div className="card border-red-200 bg-red-50">
        <div className="flex items-center gap-2 text-red-700">
          <AlertCircle className="w-5 h-5" />
          <p className="font-semibold">{error || 'Analysis not available'}</p>
        </div>
      </div>
    );
  }

  const { analysis: data } = analysis;

  // Prepare chart data
  const shotDistributionData = Object.entries(data.player_performances[0].shot_distribution).map(([type, count]) => ({
    name: type.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase()),
    value: count
  }));

  const COLORS = ['#10b981', '#3b82f6', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899'];

  const technicalScoresData = [
    { subject: 'Footwork', score: data.technical_analysis.footwork_score * 100 },
    { subject: 'Body Rotation', score: data.technical_analysis.body_rotation_score * 100 },
    { subject: 'Racket Prep', score: data.technical_analysis.racket_preparation_score * 100 },
    { subject: 'Follow Through', score: data.technical_analysis.follow_through_score * 100 },
  ];

  const rallyIntensityData = data.rallies.map(rally => ({
    rally: `Rally ${rally.rally_number}`,
    intensity: rally.intensity_level * 100,
    shots: rally.total_shots
  }));

  return (
    <div className="fade-in">
      <div className="mb-8">
        <h1 className="text-3xl font-bold mb-2">Match Analysis</h1>
        <p className="text-secondary">
          Analyzed on {new Date(data.analysis_timestamp).toLocaleDateString()}
        </p>
      </div>

      {/* Video Player Section */}
      <div className="grid grid-cols-3 gap-6 mb-8">
        <div className="col-span-2">
          <div className="card">
            <div className="video-container mb-4">
              <ReactPlayer
                url={`/api/video/${videoId}`}
                playing={isPlaying}
                controls={true}
                width="100%"
                height="100%"
                className="video-player"
                onProgress={({ playedSeconds }) => setCurrentTime(playedSeconds)}
              />
            </div>
            
            {/* Highlights */}
            <div className="border-t pt-4">
              <h3 className="font-semibold mb-3">Match Highlights</h3>
              <div className="space-y-2">
                {data.match_highlights.map((highlight, idx) => (
                  <button
                    key={idx}
                    className="w-full text-left p-3 rounded hover:bg-gray-50 transition-colors flex items-center justify-between"
                    onClick={() => {
                      // Seek to highlight timestamp
                      setCurrentTime(highlight.timestamp);
                    }}
                  >
                    <div className="flex items-center gap-3">
                      <Zap className="w-4 h-4 text-yellow-500" />
                      <div>
                        <p className="font-medium">{highlight.description}</p>
                        <p className="text-sm text-secondary">
                          {formatTime(highlight.timestamp)} - Duration: {highlight.duration.toFixed(1)}s
                        </p>
                      </div>
                    </div>
                    <Play className="w-4 h-4 text-gray-400" />
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Quick Stats */}
        <div className="space-y-4">
          <div className="card">
            <div className="flex items-center gap-3 mb-3">
              <Activity className="w-5 h-5" style={{ color: 'var(--primary-color)' }} />
              <h3 className="font-semibold">Match Overview</h3>
            </div>
            <div className="space-y-3">
              <div>
                <p className="text-sm text-secondary">Duration</p>
                <p className="text-xl font-bold">{Math.round(data.match_duration / 60)} min</p>
              </div>
              <div>
                <p className="text-sm text-secondary">Total Rallies</p>
                <p className="text-xl font-bold">{data.total_rallies}</p>
              </div>
              <div>
                <p className="text-sm text-secondary">Total Shots</p>
                <p className="text-xl font-bold">{data.total_shots}</p>
              </div>
              <div>
                <p className="text-sm text-secondary">Match Intensity</p>
                <div className="flex items-center gap-2">
                  <p className="text-xl font-bold">{(data.match_intensity * 100).toFixed(0)}%</p>
                  <div className="flex-1 bg-gray-200 rounded-full h-2">
                    <div 
                      className="h-2 rounded-full"
                      style={{ 
                        width: `${data.match_intensity * 100}%`,
                        backgroundColor: 'var(--primary-color)'
                      }}
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div className="card">
            <div className="flex items-center gap-3 mb-3">
              <Target className="w-5 h-5" style={{ color: 'var(--primary-color)' }} />
              <h3 className="font-semibold">Accuracy Stats</h3>
            </div>
            <div className="text-center">
              <p className="text-3xl font-bold" style={{ color: 'var(--primary-color)' }}>
                {(data.player_performances[0].accuracy_rate * 100).toFixed(1)}%
              </p>
              <p className="text-sm text-secondary mt-1">Overall Accuracy</p>
            </div>
            <div className="grid grid-cols-2 gap-2 mt-4 text-sm">
              <div>
                <p className="text-secondary">Winners</p>
                <p className="font-semibold">{data.player_performances[0].winner_shots}</p>
              </div>
              <div>
                <p className="text-secondary">Errors</p>
                <p className="font-semibold">{data.player_performances[0].unforced_errors}</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="border-b mb-6">
        <div className="flex gap-6">
          {['overview', 'rallies', 'technical', 'recommendations'].map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab as any)}
              className={`pb-3 px-1 font-medium transition-colors relative ${
                activeTab === tab ? 'text-primary' : 'text-gray-600 hover:text-gray-900'
              }`}
              style={{ color: activeTab === tab ? 'var(--primary-color)' : undefined }}
            >
              {tab.charAt(0).toUpperCase() + tab.slice(1)}
              {activeTab === tab && (
                <div 
                  className="absolute bottom-0 left-0 right-0 h-0.5"
                  style={{ backgroundColor: 'var(--primary-color)' }}
                />
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Tab Content */}
      {activeTab === 'overview' && (
        <div className="grid grid-cols-2 gap-6">
          {/* Shot Distribution */}
          <div className="card">
            <h3 className="text-xl font-semibold mb-4">Shot Distribution</h3>
            <ResponsiveContainer width="100%" height={300}>
              <PieChart>
                <Pie
                  data={shotDistributionData}
                  cx="50%"
                  cy="50%"
                  labelLine={false}
                  label={({ name, percent }) => `${name}: ${(percent * 100).toFixed(0)}%`}
                  outerRadius={80}
                  fill="#8884d8"
                  dataKey="value"
                >
                  {shotDistributionData.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          </div>

          {/* Rally Intensity Chart */}
          <div className="card">
            <h3 className="text-xl font-semibold mb-4">Rally Intensity</h3>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={rallyIntensityData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="rally" />
                <YAxis />
                <Tooltip />
                <Bar dataKey="intensity" fill={COLORS[0]} />
                <Bar dataKey="shots" fill={COLORS[1]} />
              </BarChart>
            </ResponsiveContainer>
          </div>

          {/* Player Strengths */}
          <div className="card">
            <h3 className="text-xl font-semibold mb-4 flex items-center gap-2">
              <Award className="w-5 h-5" style={{ color: 'var(--primary-color)' }} />
              Strengths
            </h3>
            <ul className="space-y-2">
              {data.player_performances[0].strengths.map((strength, idx) => (
                <li key={idx} className="flex items-start gap-2">
                  <div className="w-2 h-2 rounded-full mt-1.5" style={{ backgroundColor: 'var(--primary-color)' }} />
                  <span>{strength}</span>
                </li>
              ))}
            </ul>
          </div>

          {/* Areas for Improvement */}
          <div className="card">
            <h3 className="text-xl font-semibold mb-4 flex items-center gap-2">
              <TrendingUp className="w-5 h-5" style={{ color: 'var(--warning-color)' }} />
              Areas for Improvement
            </h3>
            <ul className="space-y-2">
              {data.player_performances[0].areas_for_improvement.map((area, idx) => (
                <li key={idx} className="flex items-start gap-2">
                  <div className="w-2 h-2 rounded-full mt-1.5" style={{ backgroundColor: 'var(--warning-color)' }} />
                  <span>{area}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}

      {activeTab === 'rallies' && (
        <div className="space-y-4">
          {data.rallies.map((rally) => (
            <div key={rally.rally_number} className="card">
              <div className="flex justify-between items-start mb-4">
                <div>
                  <h3 className="text-lg font-semibold">Rally {rally.rally_number}</h3>
                  <p className="text-sm text-secondary">
                    {formatTime(rally.start_time)} - {formatTime(rally.end_time)} ({rally.duration.toFixed(1)}s)
                  </p>
                </div>
                <div className="flex items-center gap-4">
                  <span className={`badge ${rally.rally_type === 'offensive' ? 'badge-danger' : rally.rally_type === 'defensive' ? 'badge-info' : 'badge-warning'}`}>
                    {rally.rally_type}
                  </span>
                  <div className="text-right">
                    <p className="text-sm text-secondary">Intensity</p>
                    <p className="font-semibold">{(rally.intensity_level * 100).toFixed(0)}%</p>
                  </div>
                </div>
              </div>
              
              <div className="grid grid-cols-3 gap-4 mb-4">
                <div>
                  <p className="text-sm text-secondary">Total Shots</p>
                  <p className="text-xl font-bold">{rally.total_shots}</p>
                </div>
                <div>
                  <p className="text-sm text-secondary">Winner</p>
                  <p className="text-xl font-bold capitalize">{rally.winner || 'None'}</p>
                </div>
                <div>
                  <p className="text-sm text-secondary">Avg Shot Power</p>
                  <p className="text-xl font-bold">
                    {(rally.shot_sequence.reduce((acc, s) => acc + s.power_estimate, 0) / rally.shot_sequence.length * 100).toFixed(0)}%
                  </p>
                </div>
              </div>

              {rally.tactical_insights.length > 0 && (
                <div className="border-t pt-3">
                  <p className="text-sm font-semibold mb-2">Tactical Insights</p>
                  <ul className="text-sm text-secondary space-y-1">
                    {rally.tactical_insights.map((insight, idx) => (
                      <li key={idx}>• {insight}</li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {activeTab === 'technical' && (
        <div className="grid grid-cols-2 gap-6">
          {/* Technical Scores Radar */}
          <div className="card">
            <h3 className="text-xl font-semibold mb-4">Technical Analysis</h3>
            <ResponsiveContainer width="100%" height={400}>
              <RadarChart data={technicalScoresData}>
                <PolarGrid />
                <PolarAngleAxis dataKey="subject" />
                <PolarRadiusAxis angle={90} domain={[0, 100]} />
                <Radar 
                  name="Score" 
                  dataKey="score" 
                  stroke={COLORS[0]} 
                  fill={COLORS[0]} 
                  fillOpacity={0.6} 
                />
                <Tooltip />
              </RadarChart>
            </ResponsiveContainer>
          </div>

          {/* Technical Recommendations */}
          <div className="card">
            <h3 className="text-xl font-semibold mb-4">Technical Recommendations</h3>
            <div className="space-y-3">
              {data.technical_analysis.technical_recommendations.map((rec, idx) => (
                <div key={idx} className="flex items-start gap-3 p-3 bg-gray-50 rounded-lg">
                  <div className="text-xl">💡</div>
                  <p className="text-sm">{rec}</p>
                </div>
              ))}
            </div>
            
            <div className="mt-6 p-4 bg-blue-50 rounded-lg">
              <p className="text-sm font-semibold text-blue-900 mb-1">Timing Consistency</p>
              <p className="text-sm text-blue-700">
                Your timing consistency score is {(data.technical_analysis.timing_consistency * 100).toFixed(1)}%.
                {data.technical_analysis.timing_consistency < 0.3 
                  ? ' Focus on maintaining consistent timing across shots.'
                  : ' Good consistency - keep it up!'}
              </p>
            </div>
          </div>

          {/* Movement Analysis */}
          <div className="card col-span-2">
            <h3 className="text-xl font-semibold mb-4">Movement & Court Coverage</h3>
            <div className="grid grid-cols-4 gap-4">
              <div className="text-center p-4 bg-gray-50 rounded-lg">
                <Users className="w-8 h-8 mx-auto mb-2" style={{ color: 'var(--primary-color)' }} />
                <p className="text-sm text-secondary">Court Coverage</p>
                <p className="text-2xl font-bold">{(data.player_performances[0].court_coverage * 100).toFixed(0)}%</p>
              </div>
              <div className="text-center p-4 bg-gray-50 rounded-lg">
                <TrendingUp className="w-8 h-8 mx-auto mb-2" style={{ color: 'var(--secondary-color)' }} />
                <p className="text-sm text-secondary">Movement Efficiency</p>
                <p className="text-2xl font-bold">{(data.player_performances[0].movement_efficiency * 100).toFixed(0)}%</p>
              </div>
              <div className="text-center p-4 bg-gray-50 rounded-lg">
                <Target className="w-8 h-8 mx-auto mb-2" style={{ color: 'var(--success-color)' }} />
                <p className="text-sm text-secondary">Shot Accuracy</p>
                <p className="text-2xl font-bold">{(data.player_performances[0].accuracy_rate * 100).toFixed(0)}%</p>
              </div>
              <div className="text-center p-4 bg-gray-50 rounded-lg">
                <Activity className="w-8 h-8 mx-auto mb-2" style={{ color: 'var(--warning-color)' }} />
                <p className="text-sm text-secondary">Match Intensity</p>
                <p className="text-2xl font-bold">{(data.match_intensity * 100).toFixed(0)}%</p>
              </div>
            </div>
          </div>
        </div>
      )}

      {activeTab === 'recommendations' && (
        <div className="grid grid-cols-2 gap-6">
          {/* Improvement Plan */}
          <div className="card">
            <h3 className="text-xl font-semibold mb-4 flex items-center gap-2">
              <Target className="w-5 h-5" style={{ color: 'var(--primary-color)' }} />
              Personalized Improvement Plan
            </h3>
            <div className="space-y-3">
              {data.improvement_plan.map((item, idx) => (
                <div key={idx} className="flex items-start gap-3">
                  <div 
                    className="w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0"
                    style={{ backgroundColor: '#f0fdf4' }}
                  >
                    <span className="text-sm font-bold" style={{ color: 'var(--primary-color)' }}>
                      {idx + 1}
                    </span>
                  </div>
                  <p>{item}</p>
                </div>
              ))}
            </div>
          </div>

          {/* Training Focus Areas */}
          <div className="card">
            <h3 className="text-xl font-semibold mb-4">Training Focus Areas</h3>
            <div className="space-y-4">
              <div className="p-4 bg-red-50 rounded-lg">
                <h4 className="font-semibold text-red-900 mb-2">High Priority</h4>
                <ul className="text-sm text-red-700 space-y-1">
                  <li>• Backhand consistency and technique</li>
                  <li>• Defensive positioning and recovery</li>
                </ul>
              </div>
              <div className="p-4 bg-yellow-50 rounded-lg">
                <h4 className="font-semibold text-yellow-900 mb-2">Medium Priority</h4>
                <ul className="text-sm text-yellow-700 space-y-1">
                  <li>• Net play variety and deception</li>
                  <li>• Serve placement and spin variation</li>
                </ul>
              </div>
              <div className="p-4 bg-green-50 rounded-lg">
                <h4 className="font-semibold text-green-900 mb-2">Maintenance</h4>
                <ul className="text-sm text-green-700 space-y-1">
                  <li>• Continue strong volley technique</li>
                  <li>• Maintain current fitness level</li>
                </ul>
              </div>
            </div>
          </div>

          {/* Next Steps */}
          <div className="card col-span-2" style={{ backgroundColor: '#f0fdf4' }}>
            <h3 className="text-xl font-semibold mb-4">Next Steps</h3>
            <div className="grid grid-cols-3 gap-4">
              <div className="text-center">
                <div className="text-3xl mb-2">📹</div>
                <h4 className="font-semibold mb-1">Record More Matches</h4>
                <p className="text-sm text-secondary">
                  Upload more videos to track your progress over time
                </p>
              </div>
              <div className="text-center">
                <div className="text-3xl mb-2">📊</div>
                <h4 className="font-semibold mb-1">Compare Performance</h4>
                <p className="text-sm text-secondary">
                  Analyze trends and improvements across multiple matches
                </p>
              </div>
              <div className="text-center">
                <div className="text-3xl mb-2">🎯</div>
                <h4 className="font-semibold mb-1">Practice Drills</h4>
                <p className="text-sm text-secondary">
                  Focus on recommended drills during training sessions
                </p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default AnalysisPage;