Deno.serve(async (req) => {
  return new Response(
    JSON.stringify({ message: "Test function from migration!" }),
    { headers: { "Content-Type": "application/json" } }
  );
});
