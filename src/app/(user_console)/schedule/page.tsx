import { Suspense } from 'react';
import CalendarView from '@/components/schedule/CalendarView';

export default function SchedulePage() {
    return (
        <div className="h-full">
            <Suspense>
                <CalendarView />
            </Suspense>
        </div>
    );
}