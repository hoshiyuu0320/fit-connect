export default function AppHeader() {
  return (
    <header className="fixed top-0 left-0 right-0 h-14 z-50 bg-white border-b border-[#E2E8F0] flex items-center px-6">
      <div className="flex items-center gap-2.5">
        <div className="w-8 h-8 bg-[#0F172A] rounded-md flex items-center justify-center text-[#14B8A6] font-bold text-[11px]">
          FC
        </div>
        <span className="font-bold text-[16px] text-[#0F172A] tracking-tight">FitConnect</span>
      </div>
    </header>
  );
}
