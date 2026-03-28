import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  const authHeader = req.headers.get("Authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  if (authHeader !== `Bearer ${serviceRoleKey}`) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  // 3日前の日付を計算
  const threeDaysAgo = new Date();
  threeDaysAgo.setDate(threeDaysAgo.getDate() - 3);
  const cutoffDate = threeDaysAgo.toISOString().split("T")[0];

  // 対象レコードを更新
  const { data, error } = await supabase
    .from("workout_assignments")
    .update({
      status: "skipped",
      updated_at: new Date().toISOString(),
    })
    .eq("status", "pending")
    .lt("assigned_date", cutoffDate)
    .select("id");

  if (error) {
    console.error("Auto-skip error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const skippedCount = data?.length ?? 0;
  console.log(`Auto-skipped ${skippedCount} overdue assignments (cutoff: ${cutoffDate})`);

  return new Response(
    JSON.stringify({
      status: "ok",
      skippedCount,
      cutoffDate,
      skippedIds: data?.map((d: { id: string }) => d.id) ?? [],
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json" },
    }
  );
});
