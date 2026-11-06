import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [tailwindcss()],
  build: {
    rollupOptions: {
      // 多页面：首页和隐私政策（路径相对于项目根目录）
      input: {
        main: 'index.html',
        privacy: 'privacy.html',
      },
    },
  },
});
