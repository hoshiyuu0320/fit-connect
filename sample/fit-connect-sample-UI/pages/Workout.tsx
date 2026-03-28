import React, { useState } from 'react';
import { Dumbbell, Activity, Calendar, TrendingUp, Play, ChevronRight } from 'lucide-react';
import { MOCK_WORKOUT_LOGS } from '../constants';

const Workout: React.FC = () => {
  const [activeType, setActiveType] = useState<'All' | 'Strength' | 'Cardio'>('All');
  const [activePeriod, setActivePeriod] = useState<'Week' | 'Month' | 'All'>('Week');
  const [expandedMonth, setExpandedMonth] = useState<string | null>('2025-12');

  const toggleMonth = (month: string) => {
    setExpandedMonth(expandedMonth === month ? null : month);
  };

  // Helper to filter logs by type
  const getFilteredLogs = () => {
    if (activeType === 'All') return MOCK_WORKOUT_LOGS;
    return MOCK_WORKOUT_LOGS.filter(log => log.type === activeType.toLowerCase());
  };

  const filteredLogs = getFilteredLogs();

  // Helper for Summary Card
  const renderSummaryCard = () => {
    let title = "Summary";
    let stats = [
      { label: "Total", value: "5", icon: "📊" },
      { label: "Strength", value: "3", icon: "💪" },
      { label: "Cardio", value: "2", icon: "🏃" }
    ];

    if (activePeriod === 'Week') {
        title = "This Week's Summary";
        if (activeType === 'Strength') {
             stats = [
                 { label: "Count", value: "3", icon: "💪" },
                 { label: "Avg Time", value: "45m", icon: "⏱️" },
                 { label: "Photos", value: "2", icon: "📸" },
             ];
        } else if (activeType === 'Cardio') {
             stats = [
                 { label: "Count", value: "2", icon: "🏃" },
                 { label: "Avg Time", value: "30m", icon: "⏱️" },
                 { label: "Photos", value: "0", icon: "📸" },
             ];
        }
    } else if (activePeriod === 'Month') {
        title = "This Month's Summary";
        stats = [
            { label: "Total", value: "18", icon: "📊" },
            { label: "Strength", value: "12", icon: "💪" },
            { label: "Cardio", value: "6", icon: "🏃" }
        ];
    } else if (activePeriod === 'All') {
        title = "Total Record";
        stats = [
            { label: "Total", value: "48", icon: "📊" },
            { label: "Strength", value: "32", icon: "💪" },
            { label: "Cardio", value: "16", icon: "🏃" }
        ];
    }

    return (
      <div className="bg-gradient-to-br from-indigo-50 to-indigo-100 p-5 rounded-3xl shadow-sm border border-indigo-100 animate-fade-in">
          <h3 className="font-bold text-slate-800 text-sm mb-4 flex items-center gap-2">
              📊 {title}
          </h3>
          <div className="grid grid-cols-3 gap-2">
              {stats.map((stat, i) => (
                  <div key={i} className="text-center p-2 bg-white/60 rounded-xl backdrop-blur-sm border border-white/50">
                      <p className="text-[10px] text-slate-500 font-bold mb-1">{stat.label}</p>
                      <p className="text-lg font-bold text-slate-800">{stat.value}</p>
                  </div>
              ))}
          </div>
      </div>
    );
  };

  // Workout Card Component
  const WorkoutCard = ({ log }: { log: typeof MOCK_WORKOUT_LOGS[0] }) => (
      <div className="bg-white p-4 rounded-2xl shadow-sm border border-slate-100 relative overflow-hidden hover:shadow-md transition-all animate-slide-up">
          <div className={`absolute left-0 top-0 bottom-0 w-1.5 ${log.type === 'strength' ? 'bg-purple-500' : 'bg-orange-500'}`}></div>
          <div className="pl-3">
              <div className="flex items-center gap-2 mb-2">
                   <div className={`w-8 h-8 rounded-lg flex items-center justify-center text-lg ${log.type === 'strength' ? 'bg-purple-50 text-purple-600' : 'bg-orange-50 text-orange-600'}`}>
                       {log.type === 'strength' ? '💪' : '🏃'}
                   </div>
                   <span className={`text-[10px] font-bold uppercase px-2 py-1 rounded-full ${log.type === 'strength' ? 'bg-purple-50 text-purple-600' : 'bg-orange-50 text-orange-600'}`}>
                       {log.type}
                   </span>
                   <span className="text-xs text-slate-400 font-medium ml-auto flex items-center gap-1">
                       <Calendar size={12} /> {log.date}
                   </span>
              </div>
              <div className="flex justify-between items-end">
                  <div>
                      <h4 className="font-bold text-slate-800">{log.title}</h4>
                      <p className="text-xs text-slate-500 mt-0.5 flex items-center gap-1">
                          ⏱️ {log.duration} • {log.time}
                      </p>
                  </div>
                  {/* Mock Images */}
                  <div className="flex -space-x-2">
                      <div className="w-6 h-6 rounded-full bg-slate-200 border-2 border-white"></div>
                      <div className="w-6 h-6 rounded-full bg-slate-200 border-2 border-white"></div>
                  </div>
              </div>
          </div>
      </div>
  );

  return (
    <div className="pb-32 space-y-6">
      
      {/* Type Filter Tabs */}
      <div className="flex bg-white p-1.5 rounded-2xl shadow-sm border border-slate-100">
         {(['All', 'Strength', 'Cardio'] as const).map((tab) => (
             <button 
                key={tab} 
                onClick={() => setActiveType(tab)}
                className={`flex-1 py-2 text-xs font-bold rounded-xl transition-all ${
                    activeType === tab 
                    ? 'bg-slate-900 text-white shadow-md' 
                    : 'text-slate-400 hover:bg-slate-50'
                }`}
             >
                 {tab === 'Strength' && <span className="mr-1">💪</span>}
                 {tab === 'Cardio' && <span className="mr-1">🏃</span>}
                 {tab}
             </button>
         ))}
      </div>

      {/* Render Summary Card based on active filters */}
      {renderSummaryCard()}

      {/* Visual Section: Calendar or Chart */}
      {activePeriod === 'Week' && (
          <div className="bg-white p-5 rounded-3xl shadow-sm border border-slate-100 animate-fade-in">
              <div className="flex justify-between items-center mb-4">
                  <h3 className="font-bold text-slate-800 text-sm">Dec 2025 (Week)</h3>
              </div>
              <div className="flex justify-between">
                  {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((day, i) => {
                      const dayNum = 8 + i; // Mock dates
                      const activity = [
                          { icon: '💪', has: true }, // M
                          { icon: null, has: false }, // T
                          { icon: '💪', has: true }, // W
                          { icon: '🏃', has: true }, // T
                          { icon: '🏃', has: true }, // F
                          { icon: '💪', has: true }, // S
                          { icon: null, has: false }, // S
                      ][i];

                      // Apply Type Filter to Calendar Visuals
                      let showIcon = activity.has;
                      if (activeType === 'Strength' && activity.icon !== '💪') showIcon = false;
                      if (activeType === 'Cardio' && activity.icon !== '🏃') showIcon = false;

                      return (
                          <div key={i} className="flex flex-col items-center gap-2">
                              <span className="text-[10px] text-slate-400 font-medium">{day}</span>
                              <div className={`w-10 h-10 rounded-xl flex flex-col items-center justify-center relative transition-all ${
                                  showIcon ? 'bg-indigo-50 border-indigo-100 text-slate-800' : 'bg-slate-50 text-slate-300'
                              }`}>
                                  {showIcon && <span className="text-sm z-10">{activity.icon}</span>}
                                  <span className={`text-[10px] font-bold z-10 ${showIcon ? 'mt-[-2px]' : ''}`}>{dayNum}</span>
                              </div>
                          </div>
                      )
                  })}
              </div>
          </div>
      )}

      {activePeriod === 'Month' && (
           <div className="bg-white p-5 rounded-3xl shadow-sm border border-slate-100 text-center py-10 animate-fade-in">
                <Calendar className="mx-auto text-slate-300 mb-2" size={32} />
                <p className="text-sm text-slate-400 font-medium">Monthly Calendar View</p>
                <p className="text-xs text-slate-300">Showing {activeType} activities</p>
           </div>
      )}

      {activePeriod === 'All' && (
          <div className="space-y-6 animate-fade-in">
              {/* Start Date */}
              <div className="bg-gradient-to-r from-amber-50 to-orange-50 p-4 rounded-2xl flex items-center gap-3 border border-amber-100">
                  <div className="w-10 h-10 bg-white/60 rounded-full flex items-center justify-center text-xl">
                      📅
                  </div>
                  <div>
                      <p className="text-[10px] font-bold text-amber-800 uppercase tracking-wide">Start Date</p>
                      <p className="text-base font-bold text-amber-900">Nov 1, 2024</p>
                  </div>
              </div>
              
              {/* Chart Placeholder */}
              <div className="bg-white p-5 rounded-3xl shadow-sm border border-slate-100">
                  <h3 className="font-bold text-slate-800 text-sm mb-4">Monthly Trend</h3>
                  <div className="h-40 bg-slate-50 rounded-xl flex items-center justify-center border-2 border-dashed border-slate-100 text-slate-400 text-xs font-medium">
                      Chart Area ({activeType})
                  </div>
              </div>
          </div>
      )}

      {/* Period Filter Tabs */}
      <div className="flex justify-center">
          <div className="inline-flex bg-slate-100 p-1 rounded-full">
              {(['Week', 'Month', 'All'] as const).map((period) => (
                  <button
                    key={period}
                    onClick={() => setActivePeriod(period)}
                    className={`px-6 py-2 rounded-full text-xs font-bold transition-all ${
                        activePeriod === period
                        ? 'bg-white text-primary-600 shadow-sm'
                        : 'text-slate-400 hover:text-slate-600'
                    }`}
                  >
                      {period}
                  </button>
              ))}
          </div>
      </div>

      {/* Log List / Accordion */}
      <div className="space-y-4">
          {activePeriod !== 'All' ? (
              <>
                  <h3 className="font-bold text-slate-800 text-sm pl-1">Recent Logs</h3>
                  <div className="space-y-3">
                      {filteredLogs.length > 0 ? (
                          filteredLogs.map(log => <WorkoutCard key={log.id} log={log} />)
                      ) : (
                          <div className="text-center py-10 text-slate-400 text-sm">
                              No logs found for this filter.
                          </div>
                      )}
                  </div>
              </>
          ) : (
              <div className="space-y-3">
                   {['2025-12', '2025-11', '2024-12'].map((month, idx) => {
                       const isExpanded = expandedMonth === month;
                       const count = [18, 14, 16][idx];
                       return (
                           <div key={month} className="bg-white rounded-2xl shadow-sm border border-slate-100 overflow-hidden">
                               <button 
                                  onClick={() => toggleMonth(month)}
                                  className={`w-full p-4 flex justify-between items-center transition-colors ${isExpanded ? 'bg-slate-50' : 'hover:bg-slate-50'}`}
                               >
                                   <div className="flex items-center gap-2 font-bold text-slate-800">
                                       <Play size={10} className={`text-slate-400 transition-transform ${isExpanded ? 'rotate-90' : ''}`} fill="currentColor" />
                                       {month}
                                   </div>
                                   <span className="text-xs text-slate-400 font-medium">{count} workouts</span>
                               </button>
                               {isExpanded && (
                                   <div className="p-4 bg-slate-50 border-t border-slate-100 space-y-3 animate-slide-up">
                                       {filteredLogs.slice(0, 2).map(log => <WorkoutCard key={log.id} log={log} />)}
                                   </div>
                               )}
                           </div>
                       )
                   })}
              </div>
          )}
      </div>

    </div>
  );
};

export default Workout;