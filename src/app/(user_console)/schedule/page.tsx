import CalendarView from '@/components/schedule/CalendarView';

export default function SchedulePage() {
    return (
        <div className="space-y-6">
            <div>
                <h1 className="text-3xl font-bold tracking-tight">スケジュール</h1>
                <p className="text-muted-foreground">
                    セッションの予約状況を確認・管理できます。
                </p>
            </div>

            <CalendarView />
        </div>
    );
}