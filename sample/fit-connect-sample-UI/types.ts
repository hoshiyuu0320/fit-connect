export type Tab = 'home' | 'weight' | 'chat' | 'food' | 'workout';

export interface WeightData {
  date: string;
  weight: number;
}

export interface FoodLog {
  id: string;
  time: string;
  type: 'Breakfast' | 'Lunch' | 'Dinner' | 'Snack';
  title: string;
  calories: number;
  imageUrl?: string;
  hasImage: boolean;
}

export interface WorkoutLog {
  id: string;
  date: string;
  time: string;
  type: 'strength' | 'cardio';
  title: string;
  duration: string;
}

export interface Message {
  id: string;
  sender: 'user' | 'trainer' | 'system';
  text?: string;
  type: 'text' | 'image' | 'log_success' | 'cheer';
  timestamp: string;
  tags?: string[];
  images?: string[];
  meta?: {
    logType?: 'weight' | 'food' | 'workout';
    value?: string;
  };
}