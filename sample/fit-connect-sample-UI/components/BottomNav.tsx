import React from 'react';
import { Home, LineChart, MessageCircle, Utensils, Dumbbell } from 'lucide-react';
import { Tab } from '../types';

interface BottomNavProps {
  activeTab: Tab;
  setActiveTab: (tab: Tab) => void;
}

const BottomNav: React.FC<BottomNavProps> = ({ activeTab, setActiveTab }) => {
  const navItems = [
    { id: 'home', icon: Home, label: 'Home' },
    { id: 'weight', icon: LineChart, label: 'Weight' },
    { id: 'chat', icon: MessageCircle, label: 'Chat', isMain: true },
    { id: 'food', icon: Utensils, label: 'Food' },
    { id: 'workout', icon: Dumbbell, label: 'Workout' },
  ];

  return (
    <div className="fixed bottom-0 left-0 right-0 bg-white border-t border-slate-100 pb-safe pt-2 px-4 pb-6 shadow-[0_-4px_6px_-1px_rgba(0,0,0,0.05)] z-50">
      <div className="flex justify-between items-end max-w-md mx-auto">
        {navItems.map((item) => {
          const isActive = activeTab === item.id;
          const Icon = item.icon;
          
          if (item.isMain) {
            return (
              <button
                key={item.id}
                onClick={() => setActiveTab(item.id as Tab)}
                className={`relative -top-5 flex flex-col items-center justify-center w-14 h-14 rounded-full shadow-lg transition-transform hover:scale-105 active:scale-95 ${
                  isActive ? 'bg-primary-600 text-white' : 'bg-primary-500 text-white'
                }`}
              >
                <Icon size={28} strokeWidth={2.5} />
              </button>
            );
          }

          return (
            <button
              key={item.id}
              onClick={() => setActiveTab(item.id as Tab)}
              className="flex flex-col items-center justify-center w-12 h-12 transition-colors duration-200"
            >
              <Icon
                size={24}
                className={`mb-1 transition-all ${
                  isActive ? 'text-primary-600' : 'text-slate-400'
                }`}
                strokeWidth={isActive ? 2.5 : 2}
              />
              <span className={`text-[10px] font-medium ${
                isActive ? 'text-primary-700' : 'text-slate-400'
              }`}>
                {item.label}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
};

export default BottomNav;