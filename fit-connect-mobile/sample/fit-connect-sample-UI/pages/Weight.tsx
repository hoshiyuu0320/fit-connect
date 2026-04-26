import React, { useState, useMemo } from 'react';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts';
import { Target, TrendingDown, Calendar, ArrowDown, ArrowUp } from 'lucide-react';
import { MOCK_WEIGHT_DATA } from '../constants';

const Weight: React.FC = () => {
  const [activePeriod, setActivePeriod] = useState('Week');
  const currentWeight = 65.2;
  const goalWeight = 60.0;
  
  // Filter data based on active period
  const chartData = useMemo(() => {
    const data = [...MOCK_WEIGHT_DATA];
    switch (activePeriod) {
      case 'Week':
        // Return last 7 entries
        return data.slice(-7);
      case 'Month':
        // Return last 30 entries (or all if less)
        return data.slice(-30);
      case '3M':
        // Return last 90 entries
        return data.slice(-90);
      case 'All':
      default:
        return data;
    }
  }, [activePeriod]);

  return (
    <div className="pb-32 space-y-6">
      
      {/* Top Stats Card - Wireframe Match */}
      <div className="bg-white p-5 rounded-3xl shadow-sm border border-slate-100">
          <div className="grid grid-cols-3 gap-2 mb-5 divide-x divide-slate-100 text-center">
             <div>
                <p className="text-[10px] text-slate-400 font-bold uppercase mb-1">Current</p>
                <p className="text-xl font-bold text-slate-800">{currentWeight}<span className="text-xs font-normal text-slate-400">kg</span></p>
             </div>
             <div>
                <p className="text-[10px] text-slate-400 font-bold uppercase mb-1">Goal</p>
                <p className="text-xl font-bold text-primary-600">{goalWeight}<span className="text-xs font-normal text-slate-400">kg</span></p>
             </div>
             <div>
                <p className="text-[10px] text-slate-400 font-bold uppercase mb-1">Left</p>
                <p className="text-xl font-bold text-slate-800">-5.2<span className="text-xs font-normal text-slate-400">kg</span></p>
             </div>
          </div>
          
          <div className="grid grid-cols-2 gap-3">
              <div className="bg-emerald-50 rounded-xl p-3 flex flex-col items-center">
                  <span className="text-[10px] text-emerald-600/70 font-medium">vs Last</span>
                  <div className="flex items-center gap-1 text-emerald-600 font-bold text-sm">
                      <ArrowDown size={14} /> 0.6kg
                  </div>
              </div>
              <div className="bg-emerald-50 rounded-xl p-3 flex flex-col items-center">
                  <span className="text-[10px] text-emerald-600/70 font-medium">vs Start</span>
                  <div className="flex items-center gap-1 text-emerald-600 font-bold text-sm">
                      <ArrowDown size={14} /> 2.3kg
                  </div>
              </div>
          </div>
      </div>

      {/* Chart Section - Wireframe Match */}
      <div className="bg-white p-5 rounded-3xl shadow-sm border border-slate-100">
        <div className="flex items-center justify-between mb-4">
            <h3 className="font-bold text-slate-800 text-sm">Weight Trend</h3>
        </div>

        {/* Period Tabs */}
        <div className="flex bg-slate-100 p-1 rounded-xl mb-4">
             {['Week', 'Month', '3M', 'All'].map((tab) => (
                 <button 
                    key={tab} 
                    onClick={() => setActivePeriod(tab)}
                    className={`flex-1 py-1.5 text-[10px] font-bold rounded-lg transition-all ${
                        activePeriod === tab 
                        ? 'bg-white text-slate-800 shadow-sm' 
                        : 'text-slate-400 hover:text-slate-600'
                    }`}
                 >
                     {tab}
                 </button>
             ))}
        </div>
        
        <div className="h-56 -ml-4">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={chartData} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
              <defs>
                <linearGradient id="colorWeight" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#2563eb" stopOpacity={0.1}/>
                  <stop offset="95%" stopColor="#2563eb" stopOpacity={0}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#f1f5f9" />
              <XAxis 
                dataKey="date" 
                axisLine={false} 
                tickLine={false} 
                tick={{ fill: '#94a3b8', fontSize: 10 }} 
                dy={10}
                interval={activePeriod === 'Week' ? 0 : 'preserveStartEnd'}
              />
              <YAxis 
                domain={['dataMin - 1', 'dataMax + 1']} 
                axisLine={false} 
                tickLine={false} 
                tick={{ fill: '#94a3b8', fontSize: 10 }} 
                width={30}
              />
              <Tooltip 
                 contentStyle={{ borderRadius: '12px', border: 'none', boxShadow: '0 10px 15px -3px rgba(0, 0, 0, 0.1)', fontSize: '12px' }}
              />
              <ReferenceLine y={goalWeight} stroke="#10b981" strokeDasharray="3 3" label={{ value: 'Goal 60kg', position: 'insideLeft', fill: '#10b981', fontSize: 10, dy: -10 }} />
              <Area 
                type="monotone" 
                dataKey="weight" 
                stroke="#2563eb" 
                strokeWidth={2.5} 
                fillOpacity={1} 
                fill="url(#colorWeight)" 
                activeDot={{ r: 5, strokeWidth: 0, fill: '#2563eb' }}
                isAnimationActive={true}
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Detail Statistics - Wireframe Match */}
      <div className="bg-white p-5 rounded-3xl shadow-sm border border-slate-100">
          <h3 className="font-bold text-slate-800 text-sm mb-3">Detailed Stats</h3>
          <div className="space-y-3">
              <div className="flex justify-between text-sm">
                  <span className="text-slate-500">Period Average</span>
                  <span className="font-bold text-slate-800">65.5 kg</span>
              </div>
              <div className="flex justify-between text-sm">
                  <span className="text-slate-500">Highest</span>
                  <span className="font-bold text-slate-800">67.5 kg <span className="text-[10px] text-slate-400 font-normal">(12/1)</span></span>
              </div>
              <div className="flex justify-between text-sm">
                  <span className="text-slate-500">Lowest</span>
                  <span className="font-bold text-slate-800">65.2 kg <span className="text-[10px] text-slate-400 font-normal">(Today)</span></span>
              </div>
          </div>
      </div>

      {/* History List */}
      <div className="bg-white rounded-3xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="p-4 bg-slate-50 border-b border-slate-100">
              <h3 className="font-bold text-slate-800 text-sm">History</h3>
          </div>
          <div>
              {chartData.slice().reverse().map((entry, idx) => (
                  <div key={idx} className="flex justify-between items-center p-4 border-b border-slate-50 last:border-0 hover:bg-slate-50 transition-colors">
                      <span className="text-sm font-medium text-slate-600">{entry.date}</span>
                      <span className="text-sm font-bold text-slate-800">{entry.weight} kg</span>
                  </div>
              ))}
          </div>
      </div>

    </div>
  );
};

export default Weight;