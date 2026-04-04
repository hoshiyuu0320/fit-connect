import React from 'react';
import { ChevronRight, Calendar, Utensils, Dumbbell, Scale, Info } from 'lucide-react';

const Home: React.FC = () => {
  return (
    <div className="pb-32 space-y-6">
      
      {/* Greeting */}
      <div className="px-1">
        <p className="text-slate-500 text-sm font-medium">Monday, Dec 9</p>
        <h2 className="text-2xl font-bold text-slate-800">Hello, Alex 👋</h2>
        <p className="text-slate-600 text-sm mt-1">Let's keep the momentum going!</p>
      </div>

      {/* Goal Card - Wireframe Match */}
      <div className="bg-gradient-to-br from-primary-600 to-primary-700 rounded-3xl p-6 text-white shadow-xl shadow-primary-500/20 relative overflow-hidden">
        {/* Background Decoration */}
        <div className="absolute top-0 right-0 w-32 h-32 bg-white/5 rounded-full -mr-10 -mt-10 blur-2xl"></div>
        
        <div className="flex items-center gap-2 mb-4">
            <div className="w-8 h-8 rounded-lg bg-white/20 flex items-center justify-center backdrop-blur-md">
                <Scale size={18} className="text-white" />
            </div>
            <h3 className="font-bold text-lg">Goal Progress</h3>
        </div>

        {/* 3 Column Stats */}
        <div className="grid grid-cols-3 gap-2 mb-6 text-center">
            <div className="bg-white/10 rounded-xl p-3 backdrop-blur-sm border border-white/10">
                <p className="text-primary-100 text-[10px] font-medium uppercase tracking-wider mb-1">Current</p>
                <p className="text-xl font-bold">65.2<span className="text-xs font-normal opacity-80">kg</span></p>
            </div>
            <div className="bg-white/10 rounded-xl p-3 backdrop-blur-sm border border-white/10">
                <p className="text-primary-100 text-[10px] font-medium uppercase tracking-wider mb-1">Goal</p>
                <p className="text-xl font-bold">60.0<span className="text-xs font-normal opacity-80">kg</span></p>
            </div>
            <div className="bg-white/90 rounded-xl p-3 shadow-sm text-primary-700">
                <p className="text-primary-600 text-[10px] font-bold uppercase tracking-wider mb-1">Left</p>
                <p className="text-xl font-bold">-5.2<span className="text-xs font-normal opacity-80">kg</span></p>
            </div>
        </div>

        {/* Progress Bar */}
        <div className="mb-2">
            <div className="flex justify-between text-xs font-medium text-primary-100 mb-2">
                <span>Achievement Rate</span>
                <span>31%</span>
            </div>
            <div className="h-2.5 bg-black/20 rounded-full overflow-hidden backdrop-blur-sm">
                <div className="h-full bg-white rounded-full w-[31%] shadow-sm"></div>
            </div>
        </div>

        {/* Deadline Info */}
        <div className="mt-4 flex items-center justify-between bg-white/10 rounded-xl px-4 py-2 border border-white/5 backdrop-blur-md">
            <div className="flex items-center gap-2 text-xs font-medium text-primary-50">
                <Calendar size={14} />
                <span>Target: Mar 15, 2026</span>
            </div>
            <span className="text-xs font-bold bg-white/20 px-2 py-0.5 rounded text-white">92 Days Left</span>
        </div>
      </div>

      {/* Daily Summary - Wireframe Match */}
      <div className="bg-white rounded-3xl p-6 shadow-sm border border-slate-100">
        <div className="flex justify-between items-center mb-6">
            <h3 className="font-bold text-slate-800 flex items-center gap-2">
                <span>Daily Summary</span>
            </h3>
            <button className="text-slate-400 hover:text-primary-600 transition-colors">
                <ChevronRight size={20} />
            </button>
        </div>

        <div className="space-y-6">
            
            {/* Meal Summary */}
            <div>
                <div className="flex justify-between items-center mb-2">
                    <div className="flex items-center gap-2.5">
                        <div className="w-8 h-8 rounded-full bg-orange-100 flex items-center justify-center text-orange-500">
                            <Utensils size={16} />
                        </div>
                        <span className="font-bold text-slate-700">Meals</span>
                    </div>
                    <span className="text-sm font-bold text-slate-800">2<span className="text-slate-400 text-xs font-normal">/3</span></span>
                </div>
                <div className="h-2 bg-slate-100 rounded-full overflow-hidden ml-11">
                    <div className="h-full bg-orange-500 rounded-full w-[67%]"></div>
                </div>
                <div className="text-right text-[10px] text-slate-400 mt-1">67% Logged</div>
            </div>

            {/* Workout Summary */}
            <div className="flex justify-between items-center py-2">
                <div className="flex items-center gap-2.5">
                    <div className="w-8 h-8 rounded-full bg-blue-100 flex items-center justify-center text-blue-500">
                        <Dumbbell size={16} />
                    </div>
                    <div>
                        <span className="font-bold text-slate-700 block leading-tight">Activity</span>
                        <span className="text-[10px] text-slate-400">This week</span>
                    </div>
                </div>
                <span className="text-sm font-bold text-slate-800">3 <span className="text-slate-400 text-xs font-normal">/ 7 Days</span></span>
            </div>

            <div className="h-px bg-slate-50"></div>

            {/* Weight Summary */}
            <div className="flex justify-between items-center">
                <div className="flex items-center gap-2.5">
                    <div className="w-8 h-8 rounded-full bg-emerald-100 flex items-center justify-center text-emerald-500">
                        <Scale size={16} />
                    </div>
                    <span className="font-bold text-slate-700">Weight</span>
                </div>
                <div className="text-right">
                    <div className="text-sm font-bold text-slate-800">65.2 kg</div>
                    <div className="text-[10px] font-bold text-emerald-500 flex items-center justify-end gap-1 bg-emerald-50 px-1.5 py-0.5 rounded mt-1">
                        -0.6kg vs yest.
                    </div>
                </div>
            </div>

        </div>
      </div>

    </div>
  );
};

export default Home;