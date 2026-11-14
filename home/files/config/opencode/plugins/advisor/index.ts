import { Model, Plugin } from "@opencode/plugin";
import { registerAdvisor } from "./runtime.mjs";

export default Plugin.define({
  id: "dotfiles.advisor",
  setup: (ctx) => registerAdvisor(ctx, Model.Ref.parse),
});
