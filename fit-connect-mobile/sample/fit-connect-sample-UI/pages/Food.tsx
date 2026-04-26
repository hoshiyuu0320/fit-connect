import React, { useState } from 'react';
import { ChevronRight, Calendar, Utensils, Image as ImageIcon, Flame, ChevronDown, Play } from 'lucide-react';
import { MOCK_FOOD_LOGS } from '../constants';
import { FoodLog } from '../types';

// Helper component for Meal Card
const MealCard: React.FC<{ log: FoodLog }> = ({ log }) => {
  let typeColor = 'bg-slate-100 text-slate-600';
  let icon = '🍽️';
  
  switch(log.type) {
      case 'Breakfast': typeColor = 'bg-amber-100 text-amber-800'; icon = '🍳'; break;
      case 'Lunch': typeColor = 'bg-blue-100 text-blue-800'; icon = '🥗'; break;
      case 'Dinner': typeColor = 'bg-rose-100 text-rose-800'; icon = '🥩'; break;
      case 'Snack': typeColor = 'bg-indigo-100 text-indigo-800'; icon = '🍎'; break;
  }

  return (
      <div className="bg-white p-4 rounded-2xl shadow-sm border border-slate-100 flex gap-3 hover:shadow-md transition-shadow cursor-pointer">
          <div className="w-20 h-20 rounded-xl bg-gradient-to-br from-blue-50 to-blue-100 flex items-center justify-center text-3xl flex-shrink-0">
              {log.imageUrl ? <img src={log.imageUrl} className="w-full h-full object-cover rounded-xl" /> : icon}
          </div>
          <div className="flex-1 min-w-0">
              <span className={`inline-block px-2.5 py-1 rounded-lg text-[10px] font-bold mb-1.5 ${typeColor}`}>
                  {log.type}
              </span>
              <h4 className="font-bold text-slate-800 mb-1 truncate">{log.title}</h4>
              <div className="flex items-center gap-3 text-xs text-slate-500">
                  <span className="flex items-center gap-1">⏰ {log.time}</span>
                  <span className="flex items-center gap-1">🔥 {log.calories} kcal</span>
              </div>
          </div>
      </div>
  );
};

interface SummaryCardProps {
    title: string;
    meals: string;
    photos: string;
    calories?: string;
    days?: string;
}

// Helper for Summary Card
const SummaryCard: React.FC<SummaryCardProps> = ({ title, meals, photos, calories, days }) => (
  <div className="bg-gradient-to-br from-blue-50 to-blue-100 p-5 rounded-2xl mb-6 shadow-sm border border-blue-100">
      <h3 className="font-bold text-slate-800 text-sm mb-4 flex items-center gap-2">
          📊 {title}
      </h3>
      <div className="space-y-3">
          <div className="flex justify-between items-center pb-3 border-b border-blue-200/50 last:border-0 last:pb-0">
              <span className="text-xs text-slate-500 font-medium flex items-center gap-2">
                  <Utensils size={14} /> Meals
              </span>
              <span className="text-sm font-bold text-slate-800">{meals}</span>
          </div>
          <div className="flex justify-between items-center pb-3 border-b border-blue-200/50 last:border-0 last:pb-0">
              <span className="text-xs text-slate-500 font-medium flex items-center gap-2">
                  <ImageIcon size={14} /> Photos
              </span>
              <span className="text-sm font-bold text-slate-800">{photos}</span>
          </div>
          <div className="flex justify-between items-center pb-3 border-b border-blue-200/50 last:border-0 last:pb-0">
              <span className="text-xs text-slate-500 font-medium flex items-center gap-2">
                  {days ? <Calendar size={14} /> : <Flame size={14} />} 
                  {days ? 'Duration' : 'Calories'}
              </span>
              <span className="text-sm font-bold text-slate-800">{days || calories}</span>
          </div>
      </div>
  </div>
);

const Food: React.FC = () => {
  const [activePeriod, setActivePeriod] = useState('Today');
  const [expandedMonth, setExpandedMonth] = useState<string | null>('2025-12');

  const toggleMonth = (month: string) => {
    setExpandedMonth(expandedMonth === month ? null : month);
  };

  const renderToday = () => (
    <div className="animate-fade-in">
        <SummaryCard 
            title="Today's Summary" 
            meals="2/3" 
            photos="4" 
            calories="800 kcal" 
        />
        <div className="space-y-4">
            <h3 className="font-bold text-slate-800 text-sm border-b-2 border-slate-100 pb-2">Dec 27 (Fri)</h3>
            {MOCK_FOOD_LOGS.map(log => <MealCard key={log.id} log={log} />)}
        </div>
    </div>
  );

  const renderWeek = () => (
    <div className="animate-fade-in">
        {/* Horizontal Week Calendar */}
        <div className="bg-white p-5 rounded-2xl shadow-sm border border-slate-100 mb-6">
            <div className="flex justify-between items-center mb-4">
                <h3 className="font-bold text-slate-800 text-sm">Dec 23 - Dec 29</h3>
            </div>
            <div className="grid grid-cols-7 gap-2">
                {['M','T','W','T','F','S','S'].map((d, i) => {
                    const dayNum = 23 + i;
                    const isToday = dayNum === 27;
                    // Mock levels
                    const level = [0,0,3,3,2,0,0][i]; 
                    const count = [0,0,3,3,2,0,0][i];
                    
                    let bg = 'bg-slate-100 text-slate-400';
                    if (level === 1) bg = 'bg-primary-200 text-primary-800';
                    if (level === 2) bg = 'bg-primary-400 text-white';
                    if (level === 3) bg = 'bg-primary-600 text-white';

                    return (
                        <div key={i} className="flex flex-col items-center gap-1.5">
                            <span className="text-[10px] text-slate-400 font-medium">{d}</span>
                            <div className={`w-full aspect-square rounded-xl flex flex-col items-center justify-center relative ${bg} ${isToday ? 'ring-2 ring-primary-600 ring-offset-2' : ''}`}>
                                <span className="text-xs font-bold">{dayNum}</span>
                                {count > 0 && <span className="text-[8px] opacity-80 mt-0.5">{count}</span>}
                            </div>
                        </div>
                    );
                })}
            </div>
        </div>

        <SummaryCard 
            title="Weekly Summary" 
            meals="8/21" 
            photos="12" 
            calories="1,850 kcal/day" 
        />

        <div className="space-y-4">
            <h3 className="font-bold text-slate-800 text-sm border-b-2 border-slate-100 pb-2">Dec 27 (Fri)</h3>
            {MOCK_FOOD_LOGS.slice(0, 1).map(log => <MealCard key={log.id} log={log} />)}
            
            <h3 className="font-bold text-slate-800 text-sm border-b-2 border-slate-100 pb-2 mt-6">Dec 26 (Thu)</h3>
            {MOCK_FOOD_LOGS.slice(1, 2).map(log => <MealCard key={log.id} log={{...log, title: 'Chicken Salad', id: '3', type: 'Lunch'}} />)}
        </div>
    </div>
  );

  const renderMonth = () => (
    <div className="animate-fade-in">
        {/* Month Calendar Grid */}
        <div className="bg-white p-5 rounded-2xl shadow-sm border border-slate-100 mb-6">
            <div className="flex justify-between items-center mb-4">
                <h3 className="font-bold text-slate-800 text-sm">December 2025</h3>
                <span className="text-xs text-slate-400">Total: 42 meals</span>
            </div>
            
            <div className="grid grid-cols-7 gap-1.5 mb-4">
                {['M','T','W','T','F','S','S'].map(d => (
                    <div key={d} className="text-center text-[10px] text-slate-400 font-bold py-1">{d}</div>
                ))}
                
                {/* 31 days + empty slots */}
                {Array.from({ length: 35 }).map((_, i) => {
                    const day = i - 2; // Offset for starting day
                    if (day < 1 || day > 31) return <div key={i} />;
                    
                    const level = (day * 7) % 4; // Randomized pattern
                    const isToday = day === 27;
                    
                    let bg = 'bg-slate-50 text-slate-300 hover:bg-slate-100';
                    if (level === 1) bg = 'bg-primary-200 text-primary-800';
                    if (level === 2) bg = 'bg-primary-400 text-white';
                    if (level === 3) bg = 'bg-primary-600 text-white';
                    
                    return (
                        <div key={i} className={`aspect-square rounded-lg flex items-center justify-center text-xs font-bold transition-transform hover:scale-110 cursor-pointer ${bg} ${isToday ? 'ring-2 ring-primary-600 ring-offset-1' : ''}`}>
                            {day}
                        </div>
                    );
                })}
            </div>
            
            <div className="flex items-center justify-end gap-3 text-[10px] text-slate-500">
                 <div className="flex items-center gap-1"><div className="w-3 h-3 rounded-sm bg-primary-600"></div>3+</div>
                 <div className="flex items-center gap-1"><div className="w-3 h-3 rounded-sm bg-primary-400"></div>2</div>
                 <div className="flex items-center gap-1"><div className="w-3 h-3 rounded-sm bg-primary-200"></div>1</div>
                 <div className="flex items-center gap-1"><div className="w-3 h-3 rounded-sm bg-slate-100"></div>0</div>
            </div>
        </div>

        <SummaryCard 
            title="Monthly Summary" 
            meals="42" 
            photos="58" 
            calories="1,920 kcal/day" 
        />
        
        <div className="space-y-4">
             <h3 className="font-bold text-slate-800 text-sm border-b-2 border-slate-100 pb-2">Dec 11 (Wed)</h3>
             <MealCard log={MOCK_FOOD_LOGS[0]} />
        </div>
    </div>
  );

  const renderAll = () => (
    <div className="animate-fade-in">
        {/* Start Date Card */}
        <div className="bg-gradient-to-br from-amber-100 to-amber-200 p-4 rounded-2xl mb-6 flex items-center gap-3 text-amber-900">
            <div className="w-10 h-10 rounded-full bg-white/40 flex items-center justify-center text-xl backdrop-blur-sm">
                📅
            </div>
            <div>
                <p className="text-xs font-bold text-amber-800 uppercase tracking-wide opacity-80">Start Date</p>
                <p className="text-base font-bold">Nov 1, 2024</p>
            </div>
        </div>

        <SummaryCard 
            title="Total Stats" 
            meals="156" 
            photos="218" 
            days="58 Days" 
        />

        {/* Chart Placeholder */}
        <div className="bg-white p-5 rounded-2xl shadow-sm border border-slate-100 mb-6">
            <h3 className="font-bold text-slate-800 text-sm mb-4">📈 Monthly Trend</h3>
            <div className="h-48 bg-gradient-to-b from-blue-50 to-blue-100 rounded-xl flex items-center justify-center text-primary-600 text-sm font-bold border border-blue-100 border-dashed">
                Chart Area
            </div>
        </div>

        {/* Accordions */}
        <div className="space-y-3">
             {['2025-12', '2025-11', '2024-12', '2024-11'].map((month, idx) => {
                 const isExpanded = expandedMonth === month;
                 const [y, m] = month.split('-');
                 const displayMonth = `${y} ${m === '12' ? 'December' : 'November'}`;
                 const count = [42, 38, 40, 36][idx];

                 return (
                     <div key={month} className="bg-white rounded-2xl shadow-sm border border-slate-100 overflow-hidden transition-all duration-300">
                         <button 
                            onClick={() => toggleMonth(month)}
                            className={`w-full p-4 flex justify-between items-center hover:bg-slate-50 transition-colors ${isExpanded ? 'bg-slate-50' : ''}`}
                         >
                             <div className="flex items-center gap-2 font-bold text-slate-800">
                                 <Play size={12} className={`text-slate-400 transition-transform duration-300 ${isExpanded ? 'rotate-90' : ''}`} fill="currentColor" />
                                 {displayMonth}
                             </div>
                             <span className="text-sm text-slate-400 font-medium">{count} meals</span>
                         </button>
                         
                         {isExpanded && (
                             <div className="bg-slate-50 border-t border-slate-100 p-4 animate-slide-down">
                                 <h4 className="text-xs font-bold text-slate-500 mb-3 uppercase tracking-wider">Latest Entries</h4>
                                 <div className="space-y-3">
                                     <MealCard log={MOCK_FOOD_LOGS[0]} />
                                     <MealCard log={MOCK_FOOD_LOGS[1]} />
                                     <button className="w-full py-2 text-center text-xs font-bold text-primary-600 hover:underline">
                                         Load more...
                                     </button>
                                 </div>
                             </div>
                         )}
                     </div>
                 )
             })}
        </div>
    </div>
  );

  return (
    <div className="pb-32 space-y-6">
      
      {/* Time Period Tabs */}
      <div className="flex bg-white p-1 rounded-2xl shadow-sm border border-slate-100 mb-2">
          {['Today', 'Week', 'Month', 'All'].map((tab) => (
              <button 
                key={tab}
                onClick={() => setActivePeriod(tab)}
                className={`flex-1 py-2 rounded-xl text-xs font-bold transition-all duration-200 ${
                    activePeriod === tab 
                    ? 'bg-primary-600 text-white shadow-md' 
                    : 'bg-transparent text-slate-400 hover:bg-slate-50'
                }`}
              >
                  {tab}
              </button>
          ))}
      </div>

      {activePeriod === 'Today' && renderToday()}
      {activePeriod === 'Week' && renderWeek()}
      {activePeriod === 'Month' && renderMonth()}
      {activePeriod === 'All' && renderAll()}

    </div>
  );
};

export default Food;