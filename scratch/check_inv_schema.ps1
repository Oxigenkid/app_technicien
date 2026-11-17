$res = Invoke-RestMethod -Uri 'https://tnkyoqpxewvjsqlkvkcf.supabase.co/rest/v1/?apikey=sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU'
$res.definitions.inventaire_camion.properties | ConvertTo-Json
