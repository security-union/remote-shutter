// Amazon Associates tracking IDs. These are the intended IDs — they MUST be
// updated to the real ones once the Associates account is approved, or the
// clicks earn nothing (links still work for shoppers either way).
export const AMAZON_TAG_WEB = 'remoteshutter-web-20';
export const AMAZON_TAG_APP = 'remoteshutter-app-20';

export interface GearItem {
  name: string;
  price: string;
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

export const GEAR_SECTIONS: GearSection[] = [
  {
    id: 'tripods',
    title: 'Phone tripods',
    sub: 'Full-height for group photos, tabletop for product shots and Mac setups. Every one of these holds the camera phone; the app gives you the live preview and the shutter.',
    items: [
      {
        name: 'UBeesize TR50 50″ tripod',
        price: '$23–30',
        why: 'The value workhorse: chest-height group shots anywhere, light enough to live in a backpack.',
        query: 'ubeesize tr50 phone tripod',
        image: 'tripod-full.jpg',
        alt: 'UBeesize TR50 full-height phone tripod',
        pick: true,
      },
      {
        name: 'Joby GorillaPod Mobile',
        price: '$25–35',
        why: "Wraps around railings, branches, and door frames — camera angles a straight tripod can't reach.",
        query: 'joby gorillapod mobile phone',
        image: 'tripod-flex.jpg',
        alt: 'Joby GorillaPod Mobile flexible tripod',
      },
      {
        name: 'Manfrotto PIXI + phone clamp',
        price: '$30–40',
        why: 'The tabletop workhorse: dead-stable for video, product shots, and long exposures on any flat surface.',
        query: 'manfrotto pixi mini tripod phone clamp',
        image: 'tripod-mini.jpg',
        alt: 'Manfrotto PIXI mini tripod with phone clamp',
      },
      {
        name: 'Manfrotto Element MII Mobile',
        price: '$120–160',
        why: 'The buy-once tripod: 63″ tall, 8 kg payload, Arca ball head — and Manfrotto’s smartphone clamp in the box.',
        query: 'manfrotto element mii mobile tripod',
        image: 'tripod-manfrotto.jpg',
        alt: 'Manfrotto Element MII Mobile tripod with smartphone clamp',
      },
    ],
  },
  {
    id: 'mounts',
    title: 'Mounts & clamps',
    sub: "Already own a camera tripod, or want the phone somewhere a tripod can't go? Start here.",
    items: [
      {
        name: 'Universal tripod phone clamp',
        price: '$10–14',
        why: 'Turns any standard tripod you already own into a Remote Shutter rig. The highest-value $12 in this list.',
        query: 'phone tripod mount clamp cold shoe',
        image: 'mount-clamp.jpg',
        alt: 'Universal tripod phone clamp',
        pick: true,
      },
      {
        name: 'MagSafe tripod mount',
        price: '$15–25',
        why: 'Snap the camera phone on and off between shots — no clamping, no fiddling while the group waits.',
        query: 'magsafe tripod mount',
        image: 'mount-magsafe.jpg',
        alt: 'MagSafe tripod mount holding an iPhone',
      },
      {
        name: 'Belkin MagSafe desk stand',
        price: '$28–35',
        why: 'The desk-studio option: holds the phone at monitor height for recording setups driven from the Mac app.',
        query: 'belkin magsafe phone stand',
        image: 'stand-desk.jpg',
        alt: 'Belkin MagSafe desk stand',
      },
      {
        name: 'Suction cup phone mount',
        price: '$12–20',
        why: 'Sticks to windows, mirrors, and tile — overhead and behind-glass angles no tripod will give you.',
        query: 'suction cup phone mount camera',
        image: 'mount-suction.jpg',
        alt: 'Suction cup phone mount',
      },
    ],
  },
  {
    id: 'lenses',
    title: 'Mobile lenses',
    sub: 'The mounted phone is the fixed half of the rig — a lens changes what it sees. Wide glass gets the whole group in frame; anamorphic turns the Mac-monitor setup into a small film set.',
    items: [
      {
        name: 'Xenvo Pro lens kit',
        price: '$35–45',
        why: 'The proven first lens: wide + macro on a padded clip that works with any phone, no case required.',
        query: 'xenvo pro lens kit',
        image: 'lens-xenvo.jpg',
        alt: 'Xenvo Pro clip-on lens kit',
      },
      {
        name: 'Sirui 1.33× anamorphic',
        price: '$70–90',
        why: 'Cinematic widescreen on a budget — the affordable way into anamorphic before committing to Moment glass.',
        query: 'sirui anamorphic lens smartphone',
        image: 'lens-sirui.jpg',
        alt: 'Sirui 1.33x anamorphic mobile lens',
      },
      {
        name: 'Sandmarc Wide',
        price: '$110–130',
        why: 'Magnesium-built wide that gets every face in the group shot without stepping back. Clip or case mount.',
        query: 'sandmarc wide lens iphone',
        image: 'lens-sandmarc.jpg',
        alt: 'Sandmarc Wide lens for iPhone',
        pick: true,
      },
      {
        name: 'Moment T-Series',
        price: '$130–150',
        why: 'The benchmark: aircraft-aluminum glass that snaps onto a Moment case. For shooters going all-in.',
        query: 'moment t-series lens',
        image: 'lens-moment.jpg',
        alt: 'Moment T-Series 18mm Wide lens',
      },
    ],
  },
];
