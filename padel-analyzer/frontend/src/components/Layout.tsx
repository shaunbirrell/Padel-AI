import React from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Home, Upload, Video, BarChart3, Menu, X } from 'lucide-react';
import { useState } from 'react';

interface LayoutProps {
  children: React.ReactNode;
}

const Layout: React.FC<LayoutProps> = ({ children }) => {
  const location = useLocation();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  const navigation = [
    { name: 'Home', href: '/', icon: Home },
    { name: 'Upload Video', href: '/upload', icon: Upload },
    { name: 'My Videos', href: '/videos', icon: Video },
  ];

  const isActive = (path: string) => location.pathname === path;

  return (
    <div className="app-container">
      {/* Navigation */}
      <nav className="bg-white shadow-md">
        <div className="container mx-auto px-4">
          <div className="flex justify-between items-center h-16">
            {/* Logo */}
            <Link to="/" className="flex items-center space-x-2">
              <BarChart3 className="h-8 w-8 text-primary" style={{ color: 'var(--primary-color)' }} />
              <span className="font-bold text-xl">Padel Analyzer</span>
            </Link>

            {/* Desktop Navigation */}
            <div className="hidden md:flex space-x-8">
              {navigation.map((item) => (
                <Link
                  key={item.name}
                  to={item.href}
                  className={`flex items-center space-x-1 px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                    isActive(item.href)
                      ? 'text-primary bg-green-50'
                      : 'text-gray-600 hover:text-primary hover:bg-gray-50'
                  }`}
                  style={{
                    color: isActive(item.href) ? 'var(--primary-color)' : undefined,
                    backgroundColor: isActive(item.href) ? '#f0fdf4' : undefined,
                  }}
                >
                  <item.icon className="h-4 w-4" />
                  <span>{item.name}</span>
                </Link>
              ))}
            </div>

            {/* Mobile menu button */}
            <button
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
              className="md:hidden p-2 rounded-md text-gray-600 hover:text-gray-900 hover:bg-gray-100"
            >
              {mobileMenuOpen ? <X className="h-6 w-6" /> : <Menu className="h-6 w-6" />}
            </button>
          </div>

          {/* Mobile Navigation */}
          {mobileMenuOpen && (
            <div className="md:hidden pb-4">
              <div className="flex flex-col space-y-2">
                {navigation.map((item) => (
                  <Link
                    key={item.name}
                    to={item.href}
                    onClick={() => setMobileMenuOpen(false)}
                    className={`flex items-center space-x-2 px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                      isActive(item.href)
                        ? 'text-primary bg-green-50'
                        : 'text-gray-600 hover:text-primary hover:bg-gray-50'
                    }`}
                    style={{
                      color: isActive(item.href) ? 'var(--primary-color)' : undefined,
                      backgroundColor: isActive(item.href) ? '#f0fdf4' : undefined,
                    }}
                  >
                    <item.icon className="h-4 w-4" />
                    <span>{item.name}</span>
                  </Link>
                ))}
              </div>
            </div>
          )}
        </div>
      </nav>

      {/* Main Content */}
      <main className="main-content">
        <div className="container">
          {children}
        </div>
      </main>

      {/* Footer */}
      <footer className="bg-gray-100 py-8 mt-12">
        <div className="container text-center text-gray-600">
          <p>&copy; 2024 Padel Analyzer. Powered by Google Cloud Video Intelligence API.</p>
        </div>
      </footer>
    </div>
  );
};

export default Layout;