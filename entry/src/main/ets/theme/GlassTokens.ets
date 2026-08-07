export class GlassTokens {
  static readonly BLUR: BlurStyle = BlurStyle.COMPONENT_REGULAR;
  static readonly BLUR_TOOLBAR: BlurStyle = BlurStyle.COMPONENT_ULTRA_THIN;
  static readonly BLUR_BUTTON: BlurStyle = BlurStyle.COMPONENT_THIN;
  static readonly BLUR_PANEL: BlurStyle = BlurStyle.COMPONENT_THICK;
  static readonly BLUR_MODAL: BlurStyle = BlurStyle.COMPONENT_ULTRA_THICK;

  static readonly BG_LIGHT: string = 'rgba(255,255,255,0.55)';
  static readonly BORDER_LIGHT: string = 'rgba(255,255,255,0.65)';
  static readonly TEXT_LIGHT: string = '#1A1A1F';

  static readonly BG_DARK: string = 'rgba(30,30,42,0.55)';
  static readonly BORDER_DARK: string = 'rgba(255,255,255,0.18)';
  static readonly TEXT_DARK: string = '#F2F2F7';

  static readonly HALO_LIGHT: string = 'rgba(120,150,255,0.55)';
  static readonly HALO_DARK: string = 'rgba(150,170,255,0.45)';

  static readonly ACCENT: string = '#6366F1';
  static readonly ACCENT_BLUE: string = '#3B82F6';
  static readonly ACCENT_SKY: string = '#60A5FA';
  static readonly PURPLE: string = '#8B5CF6';
  static readonly CYAN: string = '#22D3EE';
  static readonly WARN: string = '#F59E0B';
  static readonly DANGER: string = '#EF4444';
  static readonly SUCCESS: string = '#10B981';
  static readonly NEUTRAL_DARK: string = '#64748B';
  static readonly NEUTRAL_LIGHT: string = '#94A3B8';

  static readonly SHADOW: ShadowOptions = {
    radius: 16,
    color: 'rgba(0,0,0,0.18)',
    offsetX: 0,
    offsetY: 6
  };
}
