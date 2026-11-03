# Interactive planning companion — CodexBWAI, COMMANDER-993

Use this view for interactive `$glitch-plan` work only. Fleet execution and BWPM/FORGE are outside it.

Follow the full companion at `integrations/glitch-plan-session-view/SKILL.md`: add one explicitly agreed checkpoint block to the canonical plan, preserve stable plan/checkpoint ids, and keep the executor's current/blocked/done states consistent with its verified Progress evidence and sole START HERE. Deliberately adopt existing plans; never infer completion from prose or rewrite the whole plan to satisfy a parser.

The plugin reads that block locally on the Tern session host or over an explicitly reviewed ordinary SSH connection to the agent's machine. The operator selects the source in Tern. The helper needs no Tern environment, socket forwarding or shared cross-user store, and never writes the canonical record. No agent is prompted, restarted, assigned work or released by the view. Source failures and identity changes remain visible errors.

No hook is installed or required. The source companion is not automatically wired into managed Glitch skills. Customization/upstream adoption, exact-head review, authenticated real-client qualification and deployment remain explicit gates. Use native Tern for communication; Herdr is retired and Interceptor is unrelated.
