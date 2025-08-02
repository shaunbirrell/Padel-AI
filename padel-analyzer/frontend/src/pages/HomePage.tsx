import React from 'react';
import { Link } from 'react-router-dom';
import { Upload, BarChart3, Video, TrendingUp, Target, Users } from 'lucide-react';

const HomePage: React.FC = () => {
  const features = [
    {
      icon: BarChart3,
      title: 'Shot Analysis',
      description: 'Detailed breakdown of all your shots including forehands, backhands, volleys, and special shots like bandejas and víboras.',
    },
    {
      icon: TrendingUp,
      title: 'Rally Intelligence',
      description: 'Understand rally patterns, intensity levels, and tactical insights to improve your game strategy.',
    },
    {
      icon: Target,
      title: 'Technical Scoring',
      description: 'Get scores for technique, accuracy, power, and timing to identify areas for improvement.',
    },
    {
      icon: Video,
      title: 'Match Highlights',
      description: 'Automatically identify and clip the best rallies and shots from your matches.',
    },
    {
      icon: Users,
      title: 'Player Performance',
      description: 'Track your court coverage, movement efficiency, and shot distribution patterns.',
    },
    {
      icon: Upload,
      title: 'Easy Upload',
      description: 'Simply upload your match videos and let our AI do the analysis work for you.',
    },
  ];

  return (
    <div className="fade-in">
      {/* Hero Section */}
      <section className="text-center py-12 mb-12">
        <h1 className="text-5xl font-bold mb-6">
          Elevate Your Padel Game with AI-Powered Analysis
        </h1>
        <p className="text-xl text-secondary mb-8 max-w-3xl mx-auto">
          Upload your match videos and get professional-level insights on your shots, volleys, 
          rallies, and technique. Powered by Google Cloud Video Intelligence API.
        </p>
        <div className="flex gap-4 justify-center">
          <Link to="/upload" className="btn btn-primary">
            <Upload className="w-5 h-5" />
            Upload Your First Video
          </Link>
          <Link to="/videos" className="btn btn-outline">
            View Demo Analysis
          </Link>
        </div>
      </section>

      {/* Features Grid */}
      <section className="mb-12">
        <h2 className="text-3xl font-bold text-center mb-8">
          Comprehensive Match Analysis Features
        </h2>
        <div className="grid grid-cols-3 gap-6">
          {features.map((feature, index) => (
            <div key={index} className="card hover:shadow-lg transition-shadow">
              <feature.icon 
                className="w-12 h-12 mb-4" 
                style={{ color: 'var(--primary-color)' }}
              />
              <h3 className="text-xl font-semibold mb-2">{feature.title}</h3>
              <p className="text-secondary">{feature.description}</p>
            </div>
          ))}
        </div>
      </section>

      {/* How It Works */}
      <section className="mb-12">
        <h2 className="text-3xl font-bold text-center mb-8">How It Works</h2>
        <div className="grid grid-cols-4 gap-6">
          <div className="text-center">
            <div 
              className="w-16 h-16 rounded-full flex items-center justify-center mx-auto mb-4"
              style={{ backgroundColor: '#f0fdf4' }}
            >
              <span className="text-2xl font-bold" style={{ color: 'var(--primary-color)' }}>1</span>
            </div>
            <h3 className="font-semibold mb-2">Upload Video</h3>
            <p className="text-sm text-secondary">Upload your Padel match recording</p>
          </div>
          <div className="text-center">
            <div 
              className="w-16 h-16 rounded-full flex items-center justify-center mx-auto mb-4"
              style={{ backgroundColor: '#f0fdf4' }}
            >
              <span className="text-2xl font-bold" style={{ color: 'var(--primary-color)' }}>2</span>
            </div>
            <h3 className="font-semibold mb-2">AI Analysis</h3>
            <p className="text-sm text-secondary">Our AI analyzes every shot and rally</p>
          </div>
          <div className="text-center">
            <div 
              className="w-16 h-16 rounded-full flex items-center justify-center mx-auto mb-4"
              style={{ backgroundColor: '#f0fdf4' }}
            >
              <span className="text-2xl font-bold" style={{ color: 'var(--primary-color)' }}>3</span>
            </div>
            <h3 className="font-semibold mb-2">Get Insights</h3>
            <p className="text-sm text-secondary">Receive detailed performance metrics</p>
          </div>
          <div className="text-center">
            <div 
              className="w-16 h-16 rounded-full flex items-center justify-center mx-auto mb-4"
              style={{ backgroundColor: '#f0fdf4' }}
            >
              <span className="text-2xl font-bold" style={{ color: 'var(--primary-color)' }}>4</span>
            </div>
            <h3 className="font-semibold mb-2">Improve</h3>
            <p className="text-sm text-secondary">Follow personalized recommendations</p>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="text-center py-12 card" style={{ backgroundColor: '#f0fdf4' }}>
        <h2 className="text-3xl font-bold mb-4">Ready to Analyze Your Game?</h2>
        <p className="text-lg text-secondary mb-6">
          Start improving your Padel skills with data-driven insights
        </p>
        <Link to="/upload" className="btn btn-primary">
          <Upload className="w-5 h-5" />
          Upload Video Now
        </Link>
      </section>
    </div>
  );
};

export default HomePage;