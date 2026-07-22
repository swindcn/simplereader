import { json, jsonError, serviceClient } from "../_shared/transfer.ts";

export async function handler(): Promise<Response> {
  const supabase = serviceClient();
  const { data, error } = await supabase.rpc("expire_web_transfer_uploads");
  if (error) {
    console.error("transfer_cleanup_rpc_failed", error);
    return jsonError(500, "cleanup_failed", "清理过期文件失败。");
  }

  const paths = (data ?? []).map((row: { expired_storage_path: string }) =>
    row.expired_storage_path
  );
  if (paths.length > 0) {
    const removal = await supabase.storage.from("web-transfer").remove(paths);
    if (removal.error) {
      console.error("transfer_cleanup_storage_failed", removal.error);
      return jsonError(500, "cleanup_storage_failed", "清理过期文件失败。");
    }
  }

  return json({ expired: paths.length });
}

if (import.meta.main) {
  Deno.serve(handler);
}
