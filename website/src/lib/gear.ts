// Live Amazon Associates tracking IDs, registered under the securityunion-20
// account. The split lets app-driven clicks report separately from organic web
// in Amazon's Tracking ID Summary Report; AmazonLink picks between them on
// ?src=app. Both must exist in Associates Central — an unregistered tag still
// links fine for shoppers but attributes nothing.
export const AMAZON_TAG_WEB = 'remoteshutter-web-20';
export const AMAZON_TAG_APP = 'remoteshutter-app-20';

export interface GearItem {
  name: string;
  /** editorial price band — deliberately not a number: we have no
   *  licensed live price source, and a stale one is worse than none */
  tier: string;
  /** two-or-three-word "if you want…" label for the section quick guide */
  bestFor: string;
  why: string;
  /** Amazon search query the buy button points at */
  query: string;
  /** filename under public/gear/ */
  image: string;
  alt: string;
  pick?: boolean;
}

export interface GearSection {
  id: string;
  title: string;
  sub: string;
  items: GearItem[];
}

/** Catalog order puts "Our pick" first so the undecided reader meets the
 *  default choice before the alternatives — the rest keep author order. */
export function pickFirst(items: GearItem[]): GearItem[] {
  return [...items].sort(
    (a, b) => Number(b.pick ?? false) - Number(a.pick ?? false)
  );
}

export const GEAR_SECTIONS: GearSection[] = [
  {
    id: 'tripods',
    title: 'Phone tripods',
    sub: 'Full-height for groups, tabletop for products and Mac setups.',
    items: [
      {
        name: 'UBeesize TR50 50″ tripod',
        bestFor: 'Best overall',
        tier: 'Budget',
        why: 'Chest-height group shots anywhere, light enough for a backpack.',
        query: 'ubeesize tr50 phone tripod',
        image: 'tripod-full.jpg',
        alt: 'UBeesize TR50 full-height phone tripod',
        pick: true,
      },
      {
        name: 'Joby GorillaPod Mobile',
        bestFor: 'Odd angles',
        tier: 'Budget',
        why: 'Wraps around railings and branches for angles no tripod can reach.',
        query: 'joby gorillapod mobile phone',
        image: 'tripod-flex.jpg',
        alt: 'Joby GorillaPod Mobile flexible tripod',
      },
      {
        name: 'Manfrotto PIXI + phone clamp',
        bestFor: 'Tabletop & video',
        tier: 'Mid-range',
        why: 'Dead-stable video and product shots on any flat surface.',
        query: 'manfrotto pixi mini tripod phone clamp',
        image: 'tripod-mini.jpg',
        alt: 'Manfrotto PIXI mini tripod with phone clamp',
      },
      {
        name: 'Manfrotto Element MII Mobile',
        bestFor: 'Buy-once upgrade',
        tier: 'Premium',
        why: 'The buy-once tripod: 63″ tall, 8 kg payload, clamp included.',
        query: 'manfrotto element mii mobile tripod',
        image: 'tripod-manfrotto.jpg',
        alt: 'Manfrotto Element MII Mobile tripod with smartphone clamp',
      },
    ],
  },
  {
    id: 'mounts',
    title: 'Mounts & clamps',
    sub: 'For the tripod you already own — or spots no tripod can reach.',
    items: [
      {
        name: 'Universal tripod phone clamp',
        bestFor: 'Own a tripod already',
        tier: 'Budget',
        why: 'Turns any tripod into a Remote Shutter rig — best value here.',
        query: 'phone tripod mount clamp cold shoe',
        image: 'mount-clamp.jpg',
        alt: 'Universal tripod phone clamp',
        pick: true,
      },
      {
        name: 'MagSafe tripod mount',
        bestFor: 'Fastest on/off',
        tier: 'Budget',
        why: 'Snap the phone on and off between shots — no fiddling.',
        query: 'magsafe tripod mount',
        image: 'mount-magsafe.jpg',
        alt: 'MagSafe tripod mount holding an iPhone',
      },
      {
        name: 'Belkin MagSafe desk stand',
        bestFor: 'Desk setups',
        tier: 'Mid-range',
        why: 'Holds the phone at monitor height for Mac-driven recording.',
        query: 'belkin magsafe phone stand',
        image: 'stand-desk.jpg',
        alt: 'Belkin MagSafe desk stand',
      },
      {
        name: 'Suction cup phone mount',
        bestFor: 'Glass & tile angles',
        tier: 'Budget',
        why: 'Sticks to windows, mirrors, and tile for behind-glass angles.',
        query: 'suction cup phone mount camera',
        image: 'mount-suction.jpg',
        alt: 'Suction cup phone mount',
      },
    ],
  },
  {
    id: 'lenses',
    title: 'Mobile lenses',
    sub: 'Change what the mounted phone sees — wide glass gets everyone in.',
    items: [
      {
        name: 'Xenvo Pro lens kit',
        bestFor: 'First lens',
        tier: 'Budget',
        why: 'Wide + macro on a clip that fits any phone, no case needed.',
        query: 'xenvo pro lens kit',
        image: 'lens-xenvo.jpg',
        alt: 'Xenvo Pro clip-on lens kit',
      },
      {
        name: 'Sirui 1.33× anamorphic',
        bestFor: 'Cinematic look',
        tier: 'Mid-range',
        why: 'Cinematic widescreen on a budget.',
        query: 'sirui anamorphic lens smartphone',
        image: 'lens-sirui.jpg',
        alt: 'Sirui 1.33x anamorphic mobile lens',
      },
      {
        name: 'Sandmarc Wide',
        bestFor: 'Best overall',
        tier: 'Premium',
        why: 'Every face in the shot without stepping back. Clip or case mount.',
        query: 'sandmarc wide lens iphone',
        image: 'lens-sandmarc.jpg',
        alt: 'Sandmarc Wide lens for iPhone',
        pick: true,
      },
      {
        name: 'Moment T-Series',
        bestFor: 'Pro glass',
        tier: 'Premium',
        why: 'The benchmark glass for shooters going all-in.',
        query: 'moment t-series lens',
        image: 'lens-moment.jpg',
        alt: 'Moment T-Series 18mm Wide lens',
      },
    ],
  },
];
