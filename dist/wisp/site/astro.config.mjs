import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

export default defineConfig({
  site: "https://callistobound.github.io",
  base: "/wisp",
  integrations: [
    starlight({
      title: "Wisp",
      social: [
        { icon: "github", label: "GitHub", href: "https://github.com/callistobound/wisp" },
      ],
      sidebar: [
        { label: "Reference", items: ["config", "actions", "commands"] },
      ],
    }),
  ],
});
