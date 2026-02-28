'use client';

import {
    AlertDialog,
    AlertDialogAction,
    AlertDialogCancel,
    AlertDialogContent,
    AlertDialogDescription,
    AlertDialogFooter,
    AlertDialogHeader,
    AlertDialogTitle,
} from "@/components/ui/alert-dialog"

interface RecurrenceDeleteDialogProps {
    isOpen: boolean;
    onClose: () => void;
    onDeleteSingle: () => void;
    onDeleteFromDate: () => void;
    isLoading?: boolean;
}

export default function RecurrenceDeleteDialog({
    isOpen,
    onClose,
    onDeleteSingle,
    onDeleteFromDate,
    isLoading = false,
}: RecurrenceDeleteDialogProps) {
    return (
        <AlertDialog open={isOpen} onOpenChange={onClose}>
            <AlertDialogContent>
                <AlertDialogHeader>
                    <AlertDialogTitle>繰り返しセッションの削除</AlertDialogTitle>
                    <AlertDialogDescription>
                        このセッションのみ削除しますか？それとも、以降の繰り返しセッションもすべて削除しますか？
                    </AlertDialogDescription>
                </AlertDialogHeader>
                <AlertDialogFooter className="flex gap-2">
                    <AlertDialogCancel disabled={isLoading}>キャンセル</AlertDialogCancel>
                    <AlertDialogAction
                        onClick={onDeleteSingle}
                        disabled={isLoading}
                        className="bg-gray-600 hover:bg-gray-700"
                    >
                        このセッションのみ
                    </AlertDialogAction>
                    <AlertDialogAction
                        onClick={onDeleteFromDate}
                        disabled={isLoading}
                        className="bg-red-600 hover:bg-red-700"
                    >
                        以降すべて
                    </AlertDialogAction>
                </AlertDialogFooter>
            </AlertDialogContent>
        </AlertDialog>
    );
}
