const jwt = require('jsonwebtoken');
const User = require('../models/User');

const protect = async (req, res, next) => {
  let token;

  if (req.headers.authorization && req.headers.authorization.startsWith('Bearer')) {
    try {
      // Get token from header
      token = req.headers.authorization.split(' ')[1];

      // Verify token
      const decoded = jwt.verify(token, process.env.JWT_SECRET);

      // Get user from the token
      req.user = await User.findById(decoded.id).select('-password');

      if (!req.user) {
        return res.status(401).json({ error: 'User not found' });
      }

      if (!req.user.isActive) {
        return res.status(401).json({ error: 'Account is deactivated' });
      }

      next();
    } catch (error) {
      console.error('Token verification failed:', error);
      return res.status(401).json({ error: 'Not authorized, token failed' });
    }
  } else {
    return res.status(401).json({ error: 'Not authorized, no token' });
  }
};

const authorize = (...roles) => {
  return (req, res, next) => {
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({
        error: `User role ${req.user.role} is not authorized to access this route`
      });
    }
    next();
  };
};

const checkSubscription = (req, res, next) => {
  const user = req.user;
  
  // Check if user has videos remaining
  if (user.subscription.videosRemaining <= 0) {
    // Check if reset date has passed
    if (new Date() > user.subscription.resetDate) {
      // Reset videos based on plan
      const videosPerMonth = {
        free: 3,
        pro: 20,
        premium: 100
      };
      
      user.subscription.videosRemaining = videosPerMonth[user.subscription.plan] || 3;
      user.subscription.resetDate = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days
      user.save();
    } else {
      return res.status(403).json({
        error: 'Video upload limit reached',
        message: `You have used all your monthly video uploads. Upgrade your plan or wait until ${user.subscription.resetDate.toDateString()}`
      });
    }
  }
  
  next();
};

module.exports = { protect, authorize, checkSubscription };