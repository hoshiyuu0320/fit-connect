import React, { useState } from 'react';
import { Mail, Lock, Eye, EyeOff, ArrowRight, ArrowLeft } from 'lucide-react';

interface LoginProps {
  onLogin: () => void;
  onSwitchToSignup: () => void;
}

const Login: React.FC<LoginProps> = ({ onLogin, onSwitchToSignup }) => {
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!email || !password) return;
    
    setIsLoading(true);
    // Simulate API call
    setTimeout(() => {
      setIsLoading(false);
      onLogin();
    }, 1000);
  };

  return (
    <div className="min-h-screen bg-white flex flex-col px-6 py-10 animate-fade-in relative">
      {/* Background Decorative Elements */}
      <div className="absolute top-[-50px] right-[-50px] w-48 h-48 bg-primary-50 rounded-full blur-3xl -z-10"></div>
      <div className="absolute bottom-[-50px] left-[-20px] w-64 h-64 bg-blue-50 rounded-full blur-3xl -z-10"></div>

      <div className="flex-1 flex flex-col justify-center max-w-sm mx-auto w-full">
        <div className="mb-10 text-center">
            <div className="w-16 h-16 bg-gradient-to-br from-primary-500 to-primary-600 rounded-2xl mx-auto flex items-center justify-center text-3xl mb-6 shadow-lg shadow-primary-500/30">
                💪
            </div>
            <h1 className="text-3xl font-bold text-slate-900 mb-2 tracking-tight">Welcome Back</h1>
            <p className="text-slate-500 text-sm">Sign in to continue your fitness journey</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-5">
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
                <div className="flex justify-between items-center ml-1">
                    <label className="text-xs font-bold text-slate-700">Password</label>
                    <button type="button" className="text-xs font-bold text-primary-600 hover:text-primary-700">Forgot?</button>
                </div>
                <div className="relative group">
                    <div className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-primary-600 transition-colors">
                        <Lock size={20} />
                    </div>
                    <input 
                        type={showPassword ? "text" : "password"}
                        value={password}
                        onChange={(e) => setPassword(e.target.value)}
                        className="w-full bg-slate-50 border border-slate-200 rounded-2xl py-3.5 pl-12 pr-12 text-sm font-medium text-slate-800 outline-none focus:border-primary-500 focus:ring-4 focus:ring-primary-500/10 transition-all placeholder:text-slate-400"
                        placeholder="••••••••"
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
            </div>

            <button 
                type="submit" 
                disabled={isLoading}
                className="w-full bg-slate-900 text-white font-bold rounded-2xl py-4 shadow-lg shadow-slate-900/20 active:scale-[0.98] transition-all flex items-center justify-center gap-2 hover:bg-slate-800 disabled:opacity-70 disabled:cursor-not-allowed mt-4"
            >
                {isLoading ? (
                    <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                ) : (
                    <>
                        Log In <ArrowRight size={20} />
                    </>
                )}
            </button>
        </form>

        <div className="mt-8 text-center">
            <div className="relative mb-6">
                <div className="absolute inset-0 flex items-center">
                    <div className="w-full border-t border-slate-100"></div>
                </div>
                <div className="relative flex justify-center text-xs">
                    <span className="bg-white px-2 text-slate-400">Or continue with</span>
                </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
                <button className="flex items-center justify-center gap-2 bg-white border border-slate-100 py-3 rounded-2xl text-sm font-bold text-slate-700 hover:bg-slate-50 transition-colors">
                   <span className="text-lg">G</span> Google
                </button>
                <button className="flex items-center justify-center gap-2 bg-white border border-slate-100 py-3 rounded-2xl text-sm font-bold text-slate-700 hover:bg-slate-50 transition-colors">
                   <span className="text-lg"></span> Apple
                </button>
            </div>
        </div>

        <p className="mt-10 text-center text-sm text-slate-500">
            Don't have an account?{' '}
            <button onClick={onSwitchToSignup} className="font-bold text-primary-600 hover:text-primary-700">
                Sign up
            </button>
        </p>
      </div>
    </div>
  );
};

export default Login;