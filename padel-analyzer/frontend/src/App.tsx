import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import Layout from './components/Layout';
import HomePage from './pages/HomePage';
import UploadPage from './pages/UploadPage';
import AnalysisPage from './pages/AnalysisPage';
import VideosPage from './pages/VideosPage';
import './App.css';

function App() {
  return (
    <Router>
      <Layout>
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/upload" element={<UploadPage />} />
          <Route path="/videos" element={<VideosPage />} />
          <Route path="/analysis/:videoId" element={<AnalysisPage />} />
        </Routes>
      </Layout>
    </Router>
  );
}

export default App;
