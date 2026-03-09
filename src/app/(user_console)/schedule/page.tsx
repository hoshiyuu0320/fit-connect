import { Suspense } from 'react';
import CalendarView from '@/components/schedule/CalendarView';
import { ScheduleSkeleton } from '@/components/schedule/ScheduleSkeleton';

export default function SchedulePage() {
    return (
        <div className="h-full">
            <Suspense fallback={<ScheduleSkeleton />}>
                <CalendarView />
            </Suspense>
        </div>
    );
}
