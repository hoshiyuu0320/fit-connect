import React, { useState, useRef, useEffect } from 'react';
import { Send, Camera, Plus, ChevronDown, Hash, Image as ImageIcon } from 'lucide-react';
import { MOCK_MESSAGES } from '../constants';
import { Message } from '../types';

const ChatLog: React.FC = () => {
  const [messages, setMessages] = useState<Message[]>(MOCK_MESSAGES);
  const [inputValue, setInputValue] = useState('');
  const [showTagSuggestions, setShowTagSuggestions] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  // Simple detection for # to show tags
  useEffect(() => {
    if (inputValue.includes('#')) {
        setShowTagSuggestions(true);
    } else {
        setShowTagSuggestions(false);
    }
  }, [inputValue]);

  const handleSend = () => {
    if (!inputValue.trim()) return;

    // Basic tag parsing for demo
    const extractedTags: string[] = [];
    if (inputValue.includes('#meal')) extractedTags.push('Dining: Breakfast');
    if (inputValue.includes('#weight')) extractedTags.push('Weight');
    if (inputValue.includes('#run')) extractedTags.push('Activity: Cardio');

    const cleanText = inputValue.replace(/#\w+/g, '').trim();

    const newUserMsg: Message = {
      id: Date.now().toString(),
      sender: 'user',
      text: cleanText || inputValue, // Fallback if only tags
      type: 'text',
      timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
      tags: extractedTags.length > 0 ? extractedTags : undefined
    };

    setMessages(prev => [...prev, newUserMsg]);
    setInputValue('');
    setShowTagSuggestions(false);

    // Simulate system/trainer response logic
    setTimeout(() => {
      let responseMsg: Message | null = null;
      
      if (extractedTags.includes('Weight')) {
         responseMsg = {
             id: (Date.now() + 1).toString(),
             sender: 'trainer',
             type: 'text',
             text: "Thanks for logging! Keep it consistent.",
             timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
         }
      } else if (extractedTags.some(t => t.includes('Dining'))) {
          // Add system message first
          setMessages(prev => [...prev, {
              id: (Date.now() + 0.5).toString(),
              sender: 'system',
              type: 'log_success',
              text: "✨ Meal record automatically created",
              timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
          }]);
      }
    }, 800);
  };

  const addTag = (tag: string) => {
      setInputValue(prev => prev + (prev.length > 0 ? ' ' : '') + tag + ' ');
      setShowTagSuggestions(false);
  }

  return (
    <div className="flex flex-col h-[calc(100vh-140px)] -mx-4">
      
      {/* Sticky Trainer Header - Wireframe Match */}
      <div className="bg-white border-b border-slate-100 px-4 py-3 sticky top-0 z-10 flex items-center justify-between shadow-sm">
          <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-full bg-slate-200 overflow-hidden relative">
                  <img src="https://picsum.photos/seed/trainer/100/100" alt="Trainer" className="w-full h-full object-cover" />
                  <div className="absolute bottom-0 right-0 w-2.5 h-2.5 bg-green-500 border-2 border-white rounded-full"></div>
              </div>
              <div>
                  <h3 className="font-bold text-slate-800 text-sm leading-tight">Coach Sarah</h3>
                  <p className="text-xs text-green-600 font-medium">Online</p>
              </div>
          </div>
          <button className="p-2 text-slate-400 hover:bg-slate-50 rounded-full">
              <ChevronDown size={20} />
          </button>
      </div>

      {/* Chat Area */}
      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-5 bg-slate-50/50">
        {/* Date Divider */}
        <div className="flex justify-center mb-4">
            <span className="bg-white border border-slate-100 px-3 py-1 rounded-full text-[10px] font-bold text-slate-400 shadow-sm">
                Today, Dec 27 (Fri)
            </span>
        </div>
        
        {messages.map((msg) => {
          const isUser = msg.sender === 'user';
          const isSystem = msg.sender === 'system';
          
          if (isSystem) {
             return (
                 <div key={msg.id} className="flex justify-center my-2">
                     <div className="bg-amber-50 text-amber-700 px-4 py-1.5 rounded-full text-xs font-bold border border-amber-100 flex items-center gap-2 shadow-sm animate-fade-in">
                         {msg.text}
                     </div>
                 </div>
             )
          }

          return (
            <div key={msg.id} className={`flex ${isUser ? 'justify-end' : 'justify-start'} animate-slide-up`}>
               {!isUser && (
                   <div className="w-8 h-8 rounded-full bg-slate-200 mr-2 self-start overflow-hidden flex-shrink-0 mt-1">
                       <img src="https://picsum.photos/seed/trainer/100/100" className="w-full h-full object-cover" />
                   </div>
               )}
              
              <div className="flex flex-col max-w-[85%]">
                  <div
                    className={`p-3.5 shadow-sm relative ${
                      isUser
                        ? 'bg-primary-600 text-white rounded-2xl rounded-tr-sm'
                        : 'bg-white text-slate-800 rounded-2xl rounded-tl-sm border border-slate-100'
                    }`}
                  >
                    {/* Text Content */}
                    {msg.text && <p className="text-sm leading-relaxed whitespace-pre-wrap">{msg.text}</p>}

                    {/* Tags */}
                    {msg.tags && msg.tags.length > 0 && (
                        <div className="flex flex-wrap gap-1.5 mt-2">
                            {msg.tags.map(tag => (
                                <span key={tag} className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-lg text-[10px] font-bold ${
                                    isUser ? 'bg-white/20 text-white' : 'bg-primary-50 text-primary-600'
                                }`}>
                                    {tag.includes('Dining') && '🍽️'}
                                    {tag.includes('Weight') && '⚖️'}
                                    {tag.includes('Activity') && '🏃'}
                                    {tag}
                                </span>
                            ))}
                        </div>
                    )}

                    {/* Image Grid */}
                    {msg.images && msg.images.length > 0 && (
                        <div className="grid grid-cols-3 gap-1 mt-2 rounded-lg overflow-hidden">
                            {msg.images.map((img, idx) => (
                                <div key={idx} className="aspect-square bg-black/10">
                                    <img src={img} alt="attachment" className="w-full h-full object-cover" />
                                </div>
                            ))}
                        </div>
                    )}
                  </div>
                  
                  {/* Timestamp */}
                  <span className={`text-[10px] mt-1 text-slate-400 ${isUser ? 'text-right' : 'text-left ml-1'}`}>
                      {msg.timestamp}
                  </span>
              </div>
            </div>
          );
        })}
        <div ref={messagesEndRef} />
      </div>

      {/* Input Area - Wireframe Match */}
      <div className="bg-white border-t border-slate-100 pb-safe z-20">
        
        {/* Suggestion Bar (Conditional) */}
        {showTagSuggestions && (
            <div className="px-4 py-3 bg-white border-b border-slate-50 flex gap-2 overflow-x-auto no-scrollbar animate-slide-in">
                <button onClick={() => addTag('#meal')} className="px-3 py-1.5 bg-slate-100 hover:bg-primary-50 hover:text-primary-600 hover:border-primary-200 border border-transparent rounded-full text-xs font-bold text-slate-600 transition-colors">🍽️ #Dining</button>
                <button onClick={() => addTag('#weight')} className="px-3 py-1.5 bg-slate-100 hover:bg-primary-50 hover:text-primary-600 hover:border-primary-200 border border-transparent rounded-full text-xs font-bold text-slate-600 transition-colors">⚖️ #Weight</button>
                <button onClick={() => addTag('#run')} className="px-3 py-1.5 bg-slate-100 hover:bg-primary-50 hover:text-primary-600 hover:border-primary-200 border border-transparent rounded-full text-xs font-bold text-slate-600 transition-colors">🏃 #Activity</button>
            </div>
        )}

        <div className="p-3 px-4 flex items-end gap-3">
            <div className="flex-1 bg-slate-100 rounded-[24px] px-4 py-2 flex items-center gap-2 focus-within:ring-2 focus-within:ring-primary-500/20 focus-within:bg-white transition-all">
                <button className="text-slate-400 hover:text-primary-600 transition-colors">
                    <Camera size={22} />
                </button>
                <textarea
                    value={inputValue}
                    onChange={(e) => setInputValue(e.target.value)}
                    placeholder="Message... (# for tags)"
                    rows={1}
                    className="flex-1 bg-transparent border-none outline-none text-sm text-slate-800 placeholder:text-slate-400 resize-none py-2"
                    style={{ minHeight: '24px', maxHeight: '100px' }}
                />
            </div>
            
            <button 
                onClick={handleSend}
                disabled={!inputValue.trim()}
                className={`w-12 h-12 rounded-full flex items-center justify-center transition-all shadow-md ${
                    inputValue.trim()
                    ? 'bg-primary-600 text-white hover:scale-105 hover:bg-primary-700' 
                    : 'bg-slate-200 text-slate-400'
                }`}
            >
                <Send size={20} className={inputValue.trim() ? 'ml-0.5' : ''} />
            </button>
        </div>
      </div>
    </div>
  );
};

export default ChatLog;