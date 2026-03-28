import React from 'react';
import { Bell } from 'lucide-react';

interface HeaderProps {
  title?: string;
  subtitle?: string;
  showAvatar?: boolean;
}

const Header: React.FC<HeaderProps> = ({ title = "FIT-CONNECT", subtitle, showAvatar = true }) => {
  return (
    <header className="sticky top-0 z-40 bg-white/80 backdrop-blur-md border-b border-slate-100 px-6 py-4 flex justify-between items-center transition-all duration-300">
      <div>
        <h1 className="text-xl font-bold text-slate-900 tracking-tight">{title}</h1>
        {subtitle && <p className="text-xs text-slate-500 font-medium">{subtitle}</p>}
      </div>
      <div className="flex items-center gap-4">
        <button className="relative text-slate-400 hover:text-slate-600 transition-colors">
          <Bell size={24} />
          <span className="absolute top-0 right-0 w-2.5 h-2.5 bg-accent-500 rounded-full border-2 border-white"></span>
        </button>
        {showAvatar && (
          <div className="w-10 h-10 rounded-full bg-slate-200 overflow-hidden border-2 border-white shadow-sm">
            <img src="https://picsum.photos/100/100" alt="User" className="w-full h-full object-cover" />
          </div>
        )}
      </div>
    </header>
  );
};

export default Header;