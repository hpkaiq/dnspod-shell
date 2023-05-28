<?php
// $json = file_get_contents('https://jm.dovxi.repl.co/api?url=' . $_GET['url']);
// $json = file_get_contents('http://ltjm.ml/mao.php?url=' . $_GET['url']);
// $json = file_get_contents('https://duo.serv00.net/crawler.php?url=' . $_GET['url']);
// 创建上下文流并设置请求头
$options = array(
    'http' => array(
        'header' => "User-Agent: okhttp/4.10.1\r\n"
    )
);
$context = stream_context_create($options);

// 发送HTTP请求并获取响应内容

$json = file_get_contents($_GET['url'], false, $context);


// 删除注释
$json = preg_replace('/^\s*\/\/\s?.*$/m', '', $json);

$data = json_decode($json, true);

// 检查是否存在 key 为 csp_Alist1 的内容
$exists = false;
foreach ($data['sites'] as &$site) {
    if ($site['key'] === 'csp_Alist1') {
        $exists = true;
        // 修改 ext 的值
        $site['ext'] = 'http://xx.yy/alist.json';
        break;
    }
}

// 如果不存在，则添加新的内容
if (!$exists) {
    $newSite = array(
        "key" => "csp_Alist1",
        "name" => "🅿Alist┃网盘",
        "type" => 3,
        "api" => "csp_AList",
        "searchable" => 1,
        "quickSearch" => 0,
        "filterable" => 0,
        "changeable" => 0,
        "ext" => "http://xx.yy/alist.json"
    );
    $data['sites'][] = $newSite;
}

// 将数据转换回JSON格式
$updatedJson = json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);

// 打印更新后的接口内容
echo $updatedJson;

?>
