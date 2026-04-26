import React, { useState } from 'react';
import Header from './components/Header';
import BottomNav from './components/BottomNav';
import Home from './pages/Home';
import ChatLog from './pages/ChatLog';
import Weight from './pages/Weight';
import Food from './pages/Food';
import Workout from './pages/Workout';
import Login from './pages/Login';
import Signup from './pages/Signup';
import { Tab } from './types';

type AuthState = 'loading' | 'login' | 'signup' | 'authenticated';

const App: React.FC = () => {
  const [authState, setAuthState] = useState<AuthState>('login');
  const [activeTab, setActiveTab] = useState<Tab>('home');

  const handleLogin = () => {
    setAuthState('authenticated');
  };

  const handleSignup = () => {
    setAuthState('authenticated');
  };

  if (authState === 'login') {
    return <Login onLogin={handleLogin} onSwitchToSignup={() => setAuthState('signup')} />;
  }

  if (authState === 'signup') {
    return <Signup onSignup={handleSignup} onSwitchToLogin={() => setAuthState('login')} />;
  }

  const renderContent = () => {
    switch (activeTab) {
      case 'home':
        return <Home />;
      case 'chat':
        return <ChatLog />;
      case 'weight':
        return <Weight />;
      case 'food':
        return <Food />;
      case 'workout':
        return <Workout />;
      default:
        return <Home />;
    }
  };

  const getPageTitle = () => {
    switch(activeTab) {
        case 'home': return 'Dashboard';
        case 'chat': return 'Coach Chat';
        case 'weight': return 'Body Composition';
        case 'food': return 'Nutrition Log';
        case 'workout': return 'Workout Log';
        default: return 'FIT-CONNECT';
    }
  }

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900 font-sans selection:bg-primary-200 animate-fade-in">
      <Header 
        title={getPageTitle()} 
        subtitle={activeTab === 'home' ? 'Monday, Dec 9' : undefined}
        showAvatar={true}
      />
      
      <main className="max-w-md mx-auto pt-6 px-4">
        {renderContent()}
      </main>

      <BottomNav activeTab={activeTab} setActiveTab={setActiveTab} />
    </div>
  );
};

export default App;