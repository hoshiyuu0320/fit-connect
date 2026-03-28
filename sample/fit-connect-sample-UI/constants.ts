import { WeightData, Message, FoodLog, WorkoutLog } from './types';

export const MOCK_WEIGHT_DATA: WeightData[] = [
  { date: '12/1', weight: 66.8 },
  { date: '12/2', weight: 66.5 },
  { date: '12/3', weight: 66.2 },
  { date: '12/4', weight: 66.0 },
  { date: '12/5', weight: 65.8 },
  { date: '12/6', weight: 65.9 },
  { date: '12/7', weight: 65.5 },
  { date: '12/8', weight: 65.8 },
  { date: 'Today', weight: 65.2 },
];

export const MOCK_FOOD_LOGS: FoodLog[] = [
  {
    id: '1',
    time: '07:30',
    type: 'Breakfast',
    title: 'Oatmeal & Berries',
    calories: 350,
    hasImage: true,
    imageUrl: 'https://picsum.photos/200/200?random=1',
  },
  {
    id: '2',
    time: '12:30',
    type: 'Lunch',
    title: 'Grilled Chicken Salad',
    calories: 450,
    hasImage: true,
    imageUrl: 'https://picsum.photos/200/200?random=2',
  },
];

export const MOCK_WORKOUT_LOGS: WorkoutLog[] = [
  {
    id: '1',
    date: 'Dec 13',
    time: '19:00',
    type: 'strength',
    title: 'Full Body Strength',
    duration: '45 min'
  },
  {
    id: '2',
    date: 'Dec 11',
    time: '07:00',
    type: 'cardio',
    title: 'Morning Run 5k',
    duration: '30 min'
  },
  {
    id: '3',
    date: 'Dec 10',
    time: '19:30',
    type: 'strength',
    title: 'Upper Body Power',
    duration: '40 min'
  }
];

export const MOCK_MESSAGES: Message[] = [
  {
    id: '1',
    sender: 'trainer',
    text: "Good morning! Let's do our best today 💪",
    type: 'text',
    timestamp: '09:15',
  },
  {
    id: '2',
    sender: 'user',
    text: "Good morning! Ate a solid breakfast 🍳",
    type: 'text',
    timestamp: '09:20',
    tags: ['Dining: Breakfast'],
    images: ['https://picsum.photos/200/200?random=1', 'https://picsum.photos/200/200?random=2', 'https://picsum.photos/200/200?random=3']
  },
  {
    id: '3',
    sender: 'trainer',
    text: "Great balance! Good job getting that protein in 👍",
    type: 'text',
    timestamp: '09:22',
  },
  {
    id: '4',
    sender: 'system',
    text: "✨ Meal record automatically created",
    type: 'log_success',
    timestamp: '09:22',
    meta: { logType: 'food' }
  },
  {
    id: '5',
    sender: 'user',
    text: "Weight this morning!\n65.2kg",
    type: 'text',
    timestamp: '09:25',
    tags: ['Weight'],
  },
  {
    id: '6',
    sender: 'trainer',
    text: "-0.6kg from last time! You're on track 🎉",
    type: 'text',
    timestamp: '09:26',
  },
  {
    id: '7',
    sender: 'user',
    text: "Did a 30min jog!",
    type: 'text',
    timestamp: '10:45',
    tags: ['Activity: Cardio']
  },
  {
    id: '8',
    sender: 'trainer',
    text: "Awesome! Cardio is great for fat burn 🔥",
    type: 'text',
    timestamp: '10:47',
  }
];