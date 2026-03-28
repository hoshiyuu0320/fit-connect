import React, { useState } from 'react';
import { Mail, Lock, Eye, EyeOff, User, ArrowLeft } from 'lucide-react';

interface SignupProps {
  onSignup: () => void;
  onSwitchToLogin: () => void;
}

const Signup: React.FC<SignupProps> = ({ onSignup, onSwitchToLogin }) => {
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!email || !password || !name) return;
    
    setIsLoading(true);
    // Simulate API call
    setTimeout(() => {
      setIsLoading(false);
      onSignup();
    }, 1000);
  };

  return (
    <div className="min-h-screen bg-white flex flex-col px-6 py-10 animate-fade-in relative">
      <div className="absolute top-[-50px] left-[-50px] w-64 h-64 bg-primary-50 rounded-full blur-3xl -z-10"></div>
      
      <button 
        onClick={onSwitchToLogin}
        className="absolute top-6 left-6 w-10 h-10 rounded-full bg-slate-50 flex items-center justify-center text-slate-600 hover:bg-slate-100 transition-colors"
      >
        <ArrowLeft size={20} />
      </button>

      <div className="flex-1 flex flex-col justify-center max-w-sm mx-auto w-full pt-10">
        <div className="mb-8">
            <h1 className="text-3xl font-bold text-slate-900 mb-2 tracking-tight">Create Account</h1>
            <p className="text-slate-500 text-sm">Start your healthy lifestyle today</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-1.5">
                <label className="text-xs font-bold text-slate-700 ml-1">Full Name</label>
                <div className="relative group">
                    <div className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-primary-600 transition-colors">
                        <User size={20} />
                    </div>
                    <input 
                        type="text" 
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        className="w-full bg-slate-50 border border-slate-200 rounded-2xl py-3.5 pl-12 pr-4 text-sm font-medium text-slate-800 outline-none focus:border-primary-500 focus:ring-4 focus:ring-primary-500/10 transition-all placeholder:text-slate-400"
                        placeholder="Alex Johnson"
                        required
                    />
                </div>
            </div>

            <div className="space-y-1.5">
                <label className="text-xs font-bold text-slate-700 ml-1">Email</label>
                <div className="relative group">
                    <div className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-primary-600 transition-colors">
                        <Mail size={20} />
                    </div>
                    <input 
                        type="email" 
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                        className="w-full bg-slate-50 border border-slate-200 rounded-2xl py-3.5 pl-12 pr-4 text-sm font-medium text-slate-800 outline-none focus:border-primary-500 focus:ring-4 focus:ring-primary-500/10 transition-all placeholder:text-slate-400"
                        placeholder="hello@example.com"
                        required
                    />
                </div>
            </div>

            <div className="space-y-1.5">
                <label className="text-xs font-bold text-slate-700 ml-1">Password</label>
                <div className="relative group">
                    <div className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-primary-600 transition-colors">
                        <Lock size={20} />
                    </div>
                    <input 
                        type={showPassword ? "text" : "password"}
                        value={password}
                        onChange={(e) => setPassword(e.target.value)}
                        className="w-full bg-slate-50 border border-slate-200 rounded-2xl py-3.5 pl-12 pr-12 text-sm font-medium text-slate-800 outline-none focus:border-primary-500 focus:ring-4 focus:ring-primary-500/10 transition-all placeholder:text-slate-400"
                        placeholder="Create a password"
                        required
                    />
                    <button 
                        type="button"
                        onClick={() => setShowPassword(!showPassword)}
                        className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600"
                    >
                        {showPassword ? <EyeOff size={20} /> : <Eye size={20} />}
                    </button>
                </div>
                <p className="text-[10px] text-slate-400 ml-1">Must be at least 8 characters</p>
            </div>

            <button 
                type="submit" 
                disabled={isLoading}
                className="w-full bg-primary-600 text-white font-bold rounded-2xl py-4 shadow-lg shadow-primary-500/30 active:scale-[0.98] transition-all flex items-center justify-center gap-2 hover:bg-primary-700 disabled:opacity-70 disabled:cursor-not-allowed mt-4"
            >
                {isLoading ? (
                    <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                ) : (
                    "Create Account"
                )}
            </button>
        </form>

        <p className="mt-10 text-center text-sm text-slate-500">
            Already have an account?{' '}
            <button onClick={onSwitchToLogin} className="font-bold text-primary-600 hover:text-primary-700">
                Log in
            </button>
        </p>
      </div>
    </div>
  );
};

export default Signup;