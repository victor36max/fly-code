import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"
import tailwindcss from "@tailwindcss/vite"
import liveReactPlugin from "live_react/vite-plugin"
import path from "path"

export default defineConfig(({ command }) => ({
  publicDir: "static",
  plugins: [
    liveReactPlugin(),
    react(),
    tailwindcss(),
  ],
  build: {
    target: "es2022",
    outDir: "../priv/static/assets",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        app: "./js/app.js",
      },
      output: {
        entryFileNames: "[name].js",
        chunkFileNames: "[name]-[hash].js",
        assetFileNames: "[name][extname]",
      },
    },
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "react-components"),
    },
  },
}))
