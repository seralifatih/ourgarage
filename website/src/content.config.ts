import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

const guides = defineCollection({
  loader: glob({ pattern: '*.md', base: './content/guides' }),
  schema: z.object({
    title: z.string().max(70),
    description: z.string().min(70).max(160),
    publish_date: z.coerce.date(),
    updated_date: z.coerce.date().optional(),
    keywords: z.array(z.string()).min(1),
    /** Slugs shown in the "Related guides" box; only published ones render. */
    related: z.array(z.string()).default([]),
    /** Short label for the CTA, e.g. "oil changes" → "Get reminders for oil changes". */
    cta_topic: z.string(),
    faq: z.array(z.object({ q: z.string(), a: z.string() })).default([]),
  }),
});

export const collections = { guides };
