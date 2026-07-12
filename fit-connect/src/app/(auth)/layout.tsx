import AppHeader from '@/components/AppHeader';

export default function AuthLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <>
      <AppHeader />
      <main className="pt-14">{children}</main>
    </>
  );
}
