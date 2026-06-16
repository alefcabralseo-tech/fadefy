// ============================================================
// Edge Function: criar-dono
// ------------------------------------------------------------
// Cria o login (Supabase Auth) do dono de uma barbearia e o
// perfil ligado a ela. Usa a service_role (chave SECRETA) que
// só existe no servidor — por isso NÃO pode ficar no admin.html.
//
// Deploy:  supabase functions deploy criar-dono
// O admin.html já chama esta função automaticamente.
// ============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function cors() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

Deno.serve(async (req) => {
  // pré-flight CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors() });
  }

  try {
    const { email, senha, nome, barbearia_id } = await req.json();

    if (!email || !senha || !barbearia_id) {
      throw new Error("email, senha e barbearia_id são obrigatórios");
    }

    // cliente com a chave SECRETA (service_role) — só existe no servidor
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 1) cria o usuário (login do dono)
    const { data: user, error: e1 } = await admin.auth.admin.createUser({
      email,
      password: senha,
      email_confirm: true,
    });
    if (e1) throw e1;

    // 2) cria o perfil ligado à barbearia, com papel "dono"
    const { error: e2 } = await admin.from("perfis").insert({
      id: user.user.id,
      nome,
      role: "dono",
      barbearia_id,
    });
    if (e2) throw e2;

    // 3) vincula o user_id na barbearia
    const { error: e3 } = await admin.from("barbearias")
      .update({ dono_user_id: user.user.id })
      .eq("id", barbearia_id);
    if (e3) throw e3;

    return new Response(JSON.stringify({ ok: true, user_id: user.user.id }), {
      headers: { ...cors(), "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String((err as Error).message || err) }),
      { status: 400, headers: { ...cors(), "Content-Type": "application/json" } },
    );
  }
});
