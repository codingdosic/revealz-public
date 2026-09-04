-- One-shot seed from client shop .tres / pool JSON (server-authority step 0).
-- ON CONFLICT DO NOTHING — ops edits are never overwritten on lobby restart.

INSERT INTO shop_products (
  product_id, product_type, display_name, description, price_gold, enabled,
  pack_size, weight_n, weight_r, weight_sr, weight_ur, pool_mode, pool_json,
  accessory_type, accessory_id, sort_order
) VALUES
(
  'basic_pack', 'pack', 'Basic Pack',
  '전체 기본 카드 중 5장을 랜덤하게 얻을 수 있다.',
  100, TRUE, 5, 674, 225, 75, 26, 'all_non_token', '[]'::jsonb,
  '', '', 10
),
(
  'limited_black', 'pack', 'Limited black',
  '흑색 카드 한정 획득 가능',
  150, TRUE, 5, 70, 20, 8, 2, 'explicit',
  '[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]'::jsonb,
  '', '', 20
),
(
  'limited_white', 'pack', 'Limited white',
  '백색 카드 한정 획득 가능',
  150, TRUE, 5, 70, 20, 8, 2, 'explicit',
  '[31,32,33,34,35,36,37,38,39,40,41,42,43,44,45]'::jsonb,
  '', '', 21
),
(
  'limited_red', 'pack', 'Limited red',
  '적색 카드 한정 획득 가능',
  150, TRUE, 5, 70, 20, 8, 2, 'explicit',
  '[16,17,18,19,20,21,22,23,24,25,26,27,28,29,30]'::jsonb,
  '', '', 22
),
(
  'limited_green', 'pack', 'Limited green',
  '녹색 카드 한정 획득 가능',
  150, TRUE, 5, 70, 20, 8, 2, 'explicit',
  '[47,48,49,50,51,52,53,54,55,56,57,58,59,60,61]'::jsonb,
  '', '', 23
),
(
  'limited_blue', 'pack', 'Limited blue',
  '청색 카드 한정 획득 가능',
  150, TRUE, 5, 70, 20, 8, 2, 'explicit',
  '[62,63,64,65,66,67,68,69,70,71,72,73,74,75,76]'::jsonb,
  '', '', 24
),
(
  'shop_blue_back', 'accessory', '블루', '', 200, TRUE,
  1, 0, 0, 0, 0, 'explicit', '[]'::jsonb,
  'card_back', 'blue_back', 100
),
(
  'shop_green_back', 'accessory', '그린', '', 200, TRUE,
  1, 0, 0, 0, 0, 'explicit', '[]'::jsonb,
  'card_back', 'green_back', 101
),
(
  'shop_red_back', 'accessory', '레드', '', 200, TRUE,
  1, 0, 0, 0, 0, 'explicit', '[]'::jsonb,
  'card_back', 'red_back', 102
),
(
  'shop_purple_back', 'accessory', '퍼플', '', 200, TRUE,
  1, 0, 0, 0, 0, 'explicit', '[]'::jsonb,
  'card_back', 'purple_back', 103
),
(
  'shop_cosmic_back', 'accessory', '코스믹', '', 200, TRUE,
  1, 0, 0, 0, 0, 'explicit', '[]'::jsonb,
  'card_back', 'cosmic_back', 104
),
(
  'shop_neon_back', 'accessory', '네온', '', 200, TRUE,
  1, 0, 0, 0, 0, 'explicit', '[]'::jsonb,
  'card_back', 'neon_back', 105
),
(
  'shop_icon_red', 'accessory', '레드 아이콘', '', 150, TRUE,
  1, 0, 0, 0, 0, 'explicit', '[]'::jsonb,
  'icon', 'icon_red', 110
),
(
  'shop_icon_blue', 'accessory', '블루 아이콘', '', 150, TRUE,
  1, 0, 0, 0, 0, 'explicit', '[]'::jsonb,
  'icon', 'icon_blue', 111
),
(
  'shop_field_board2', 'accessory', '레드', '', 1000, TRUE,
  1, 0, 0, 0, 0, 'explicit', '[]'::jsonb,
  'field', 'field_board2', 120
)
ON CONFLICT (product_id) DO NOTHING;

INSERT INTO app_config (config_key, config_value)
VALUES
  ('shop_catalog_revision', '1'::jsonb),
  ('min_client_version', '""'::jsonb)
ON CONFLICT (config_key) DO NOTHING;
