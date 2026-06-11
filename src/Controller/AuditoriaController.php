<?php
declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\View;
use ConectaEduca\Security\Authorization;
use ConectaEduca\Service\AuditLogService;

final class AuditoriaController
{
    public function index(): void
    {
        Authorization::requireRole("admin");

        $service = new AuditLogService();

        View::render("admin/auditoria", [
            "eventos" => $service->ultimosEventos(80),
        ]);
    }
}
